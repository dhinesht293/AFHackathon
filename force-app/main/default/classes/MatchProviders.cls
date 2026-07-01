/**
 * MatchProviders — deterministic, explainable provider matching for a Care Need.
 *
 * Matching is Apex, not LLM: hard gates first (verified, service-type, capacity,
 * location), then a weighted score normalized to 0-100. The Match_Reason is
 * assembled from the same fields that produced the score, so the explanation can
 * never drift from the math. Bulk-safe: no SOQL/DML in loops; with sharing.
 */
public with sharing class MatchProviders {
    // Scoring weights (must sum to 1.0). See design spec.
    private static final Decimal W_LOCATION = 0.40;
    private static final Decimal W_AVAILABILITY = 0.35;
    private static final Decimal W_CAPACITY = 0.15;
    private static final Decimal W_RATING = 0.10;
    private static final Integer DEFAULT_MAX_RESULTS = 3;

    public class Request {
        @InvocableVariable(required=true)
        public Id careNeedId;
        @InvocableVariable
        public Integer maxResults;
    }

    public class MatchResult {
        @InvocableVariable
        public Id providerId;
        @InvocableVariable
        public Integer score;
        @InvocableVariable
        public String reason;
    }

    public class Response {
        @InvocableVariable
        public List<MatchResult> matches;
        @InvocableVariable
        public String noMatchReason;
    }

    @InvocableMethod(label='Match Providers' description='Ranks verified providers for a Care Need using deterministic weighted scoring.')
    public static List<Response> matchProviders(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        // Bulk-load all needs in one query.
        Set<Id> needIds = new Set<Id>();
        for (Request req : requests) {
            if (req.careNeedId != null) {
                needIds.add(req.careNeedId);
            }
        }
        Map<Id, Care_Need__c> needsById = new Map<Id, Care_Need__c>(queryNeeds(needIds));

        // Bulk-load all verified providers once (small dataset in this app).
        List<Provider_Profile__c> providers = queryVerifiedProviders();

        for (Request req : requests) {
            responses.add(buildResponse(needsById.get(req.careNeedId), providers, resolveMax(req.maxResults)));
        }
        return responses;
    }

    private static Integer resolveMax(Integer requested) {
        return (requested == null || requested <= 0) ? DEFAULT_MAX_RESULTS : requested;
    }

    private static Response buildResponse(Care_Need__c need, List<Provider_Profile__c> providers, Integer maxResults) {
        Response resp = new Response();
        resp.matches = new List<MatchResult>();

        if (need == null) {
            resp.noMatchReason = 'Care need not found.';
            return resp;
        }

        Set<String> reqDays = splitMsp(need.Requested_Day__c);
        Set<String> reqBlocks = splitMsp(need.Requested_Time_Block__c);

        List<ScoredProvider> scored = new List<ScoredProvider>();
        for (Provider_Profile__c p : providers) {
            // Gate: service-type fit.
            if (!splitMsp(p.Services_Offered__c).contains(need.Care_Type__c)) {
                continue;
            }
            // Gate: capacity (null capacity treated as 1).
            Decimal capacity = (p.Capacity__c == null) ? 1 : p.Capacity__c;
            Decimal active = (p.Active_Match_Count__c == null) ? 0 : p.Active_Match_Count__c;
            if (active >= capacity) {
                continue;
            }
            // Gate: location — distance within radius, else same-city fallback.
            Decimal dist = distanceKm(need, p);
            Boolean sameCity = need.City__c != null && p.City__c != null
                && need.City__c.equalsIgnoreCase(p.City__c);
            Decimal radius = (p.Service_Radius_Km__c == null) ? 10 : p.Service_Radius_Km__c;
            if (dist != null) {
                if (dist > radius && !sameCity) {
                    continue;
                }
            } else if (!sameCity) {
                continue;
            }

            // Weighted score components (each 0..1).
            Decimal locScore = locationScore(dist, radius);
            Decimal availScore = availabilityOverlap(reqDays, reqBlocks, p);
            Decimal capScore = (capacity - active) / capacity;
            Decimal ratingScore = (p.Rating__c == null) ? 0 : (p.Rating__c / 5.0);

            Integer score = Integer.valueOf(Math.round(100 * (
                W_LOCATION * locScore
                + W_AVAILABILITY * availScore
                + W_CAPACITY * capScore
                + W_RATING * ratingScore
            )));

            String reason = buildReason(p, dist, sameCity, availScore, need);
            scored.add(new ScoredProvider(p, score, reason));
        }

        if (scored.isEmpty()) {
            resp.noMatchReason = 'No verified providers for ' + need.Care_Type__c
                + ' in ' + need.City__c + ' are available right now. Try broadening the schedule or area, or ask about support resources.';
            return resp;
        }

        scored.sort(); // score desc, then rating desc
        for (Integer i = 0; i < Math.min(maxResults, scored.size()); i++) {
            ScoredProvider sp = scored[i];
            MatchResult mr = new MatchResult();
            mr.providerId = sp.provider.Id;
            mr.score = sp.score;
            mr.reason = sp.reason;
            resp.matches.add(mr);
        }
        return resp;
    }

    /** location score: 1 - dist/radius; 1.0 when no geo (same-city fallback). */
    private static Decimal locationScore(Decimal dist, Decimal radius) {
        if (dist == null || radius == null || radius == 0) {
            return 1.0;
        }
        Decimal s = 1 - (dist / radius);
        return s < 0 ? 0 : s;
    }

    /** availability overlap over requested (day x block) cells. */
    private static Decimal availabilityOverlap(Set<String> reqDays, Set<String> reqBlocks, Provider_Profile__c p) {
        if (reqDays.isEmpty() || reqBlocks.isEmpty()) {
            return 1.0; // nothing specific requested — no penalty
        }
        Set<String> provDays = splitMsp(p.Availability_Day__c);
        Set<String> provBlocks = splitMsp(p.Availability_Time_Block__c);

        Integer requestedCells = reqDays.size() * reqBlocks.size();
        Integer covered = 0;
        for (String d : reqDays) {
            if (!provDays.contains(d)) {
                continue;
            }
            for (String b : reqBlocks) {
                if (provBlocks.contains(b)) {
                    covered++;
                }
            }
        }
        return requestedCells == 0 ? 1.0 : (Decimal.valueOf(covered) / requestedCells);
    }

    /** Haversine distance in km, or null if either geolocation is missing. */
    private static Decimal distanceKm(Care_Need__c need, Provider_Profile__c p) {
        if (need.Geolocation__Latitude__s == null || need.Geolocation__Longitude__s == null
            || p.Geolocation__Latitude__s == null || p.Geolocation__Longitude__s == null) {
            return null;
        }
        Double lat1 = need.Geolocation__Latitude__s;
        Double lon1 = need.Geolocation__Longitude__s;
        Double lat2 = p.Geolocation__Latitude__s;
        Double lon2 = p.Geolocation__Longitude__s;
        Double r = 6371; // earth radius km
        Double dLat = toRad(lat2 - lat1);
        Double dLon = toRad(lon2 - lon1);
        Double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
            + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2))
            * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return Decimal.valueOf(r * c).setScale(1);
    }

    private static Double toRad(Double deg) {
        return deg * Math.PI / 180;
    }

    /** Reason text assembled from the same fields that produced the score. */
    private static String buildReason(Provider_Profile__c p, Decimal dist, Boolean sameCity,
        Decimal availScore, Care_Need__c need) {
        List<String> parts = new List<String>();
        parts.add('Verified ' + need.Care_Type__c.toLowerCase() + ' provider');
        if (dist != null) {
            parts.add(dist.stripTrailingZeros() + ' km away');
        } else if (sameCity) {
            parts.add('in ' + p.City__c);
        }
        if (availScore >= 1) {
            parts.add('available for your full schedule');
        } else if (availScore > 0) {
            parts.add('available for part of your schedule');
        }
        if (p.Rating__c != null && p.Rating__c >= 4.5) {
            parts.add('highly rated (' + p.Rating__c + '★)');
        } else if (p.Rating__c != null) {
            parts.add('rated ' + p.Rating__c + '★');
        }
        return String.join(parts, '; ') + '.';
    }

    private static Set<String> splitMsp(String value) {
        Set<String> out = new Set<String>();
        if (String.isBlank(value)) {
            return out;
        }
        for (String s : value.split(';')) {
            if (String.isNotBlank(s)) {
                out.add(s.trim());
            }
        }
        return out;
    }

    private static List<Care_Need__c> queryNeeds(Set<Id> ids) {
        if (!Schema.SObjectType.Care_Need__c.isAccessible()) {
            return new List<Care_Need__c>();
        }
        return [
            SELECT Id, Care_Type__c, City__c, Requested_Day__c, Requested_Time_Block__c,
                   Geolocation__Latitude__s, Geolocation__Longitude__s
            FROM Care_Need__c
            WHERE Id IN :ids
            WITH USER_MODE
        ];
    }

    private static List<Provider_Profile__c> queryVerifiedProviders() {
        if (!Schema.SObjectType.Provider_Profile__c.isAccessible()) {
            return new List<Provider_Profile__c>();
        }
        return [
            SELECT Id, Name, Services_Offered__c, Availability_Day__c, Availability_Time_Block__c,
                   City__c, Service_Radius_Km__c, Capacity__c, Active_Match_Count__c, Rating__c,
                   Geolocation__Latitude__s, Geolocation__Longitude__s
            FROM Provider_Profile__c
            WHERE Verified__c = true
            WITH USER_MODE
        ];
    }

    /** Sortable wrapper: score desc, then rating desc as explicit tiebreaker. */
    private class ScoredProvider implements Comparable {
        public Provider_Profile__c provider;
        public Integer score;
        public String reason;

        public ScoredProvider(Provider_Profile__c provider, Integer score, String reason) {
            this.provider = provider;
            this.score = score;
            this.reason = reason;
        }

        public Integer compareTo(Object o) {
            ScoredProvider other = (ScoredProvider) o;
            if (this.score != other.score) {
                return other.score - this.score;
            }
            Decimal r1 = provider.Rating__c == null ? 0 : provider.Rating__c;
            Decimal r2 = other.provider.Rating__c == null ? 0 : other.provider.Rating__c;
            if (r1 == r2) {
                return 0;
            }
            return r1 > r2 ? -1 : 1;
        }
    }
}
