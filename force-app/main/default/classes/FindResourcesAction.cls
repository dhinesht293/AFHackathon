/**
 * FindResourcesAction — grounded triage/navigation lookup for the Agentforce agent.
 *
 * Returns REAL Resource__c records so the agent's answer is grounded and cited,
 * never hallucinated. Given an optional resource type and optional city, it returns
 * the matching resources: locality-specific (non-null City) first, then national
 * (blank City), each carrying its Source_URL__c so the answer can cite its source.
 *
 * Honesty over fabrication: no match => empty results + a noResultsMessage.
 * Bulk-safe: queries all resources ONCE (WITH USER_MODE), then filters/sorts/caps
 * per request in memory — no SOQL in the per-request loop. public with sharing.
 */
public with sharing class FindResourcesAction {
    private static final Integer DEFAULT_MAX_RESULTS = 5;

    public class Request {
        @InvocableVariable(
            label='Resource Type'
            description='Optional. One of: Support Group; Local Service; Benefit/Scheme; Crisis Line.'
        )
        public String resourceType;
        @InvocableVariable(label='City' description='Optional locality; blank-city records are national/global.')
        public String city;
        @InvocableVariable(label='Max Results' description='Optional cap on results (default 5).')
        public Integer maxResults;
    }

    public class ResourceResult {
        @InvocableVariable
        public String name;
        @InvocableVariable
        public String resourceType;
        @InvocableVariable
        public String summary;
        @InvocableVariable
        public String sourceUrl;
        @InvocableVariable
        public Boolean isCrisisResource;
    }

    public class Response {
        @InvocableVariable
        public List<ResourceResult> results;
        @InvocableVariable
        public Integer resultCount;
        @InvocableVariable
        public String noResultsMessage;
    }

    @InvocableMethod(
        label='Find Resources'
        description='Returns grounded, citable Resource records by type and city for navigation answers.'
    )
    public static List<Response> findResources(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        // Bulk-load ALL resources once; filter/sort/cap per request in memory.
        List<Resource__c> allResources = queryResources();

        for (Request req : requests) {
            responses.add(buildResponse(req, allResources));
        }
        return responses;
    }

    private static Response buildResponse(Request req, List<Resource__c> allResources) {
        Response resp = new Response();
        resp.results = new List<ResourceResult>();

        String type = (req == null) ? null : trimToNull(req.resourceType);
        String city = (req == null) ? null : trimToNull(req.city);
        Integer maxResults = resolveMax(req == null ? null : req.maxResults);

        // Filter: type (if provided) AND — when a city is provided — city-match OR national (blank city).
        List<Resource__c> matched = new List<Resource__c>();
        for (Resource__c r : allResources) {
            if (type != null && !type.equalsIgnoreCase(r.Resource_Type__c)) {
                continue;
            }
            if (city != null) {
                Boolean isNational = String.isBlank(r.City__c);
                Boolean isLocalMatch = String.isNotBlank(r.City__c) && city.equalsIgnoreCase(r.City__c);
                if (!isNational && !isLocalMatch) {
                    continue;
                }
            }
            matched.add(r);
        }

        // Order: locality-specific (non-null City) before national (blank City), then by Name.
        matched.sort(new ResourceComparator());

        for (Integer i = 0; i < Math.min(maxResults, matched.size()); i++) {
            resp.results.add(toResult(matched[i]));
        }
        resp.resultCount = resp.results.size();

        if (resp.results.isEmpty()) {
            resp.noResultsMessage = buildNoResultsMessage(type, city);
        }
        return resp;
    }

    private static ResourceResult toResult(Resource__c r) {
        ResourceResult rr = new ResourceResult();
        rr.name = r.Name;
        rr.resourceType = r.Resource_Type__c;
        rr.summary = r.Summary__c;
        rr.sourceUrl = r.Source_URL__c;
        rr.isCrisisResource = (r.Is_Crisis_Resource__c == true);
        return rr;
    }

    private static String buildNoResultsMessage(String type, String city) {
        String typePart = (type == null) ? 'resources' : type + ' resources';
        String cityPart = (city == null) ? '' : ' for ' + city;
        return 'No ' + typePart + cityPart
            + ' are on file right now. I can\'t make one up — try a different resource type or area,'
            + ' or ask me to broaden the search.';
    }

    private static Integer resolveMax(Integer requested) {
        return (requested == null || requested <= 0) ? DEFAULT_MAX_RESULTS : requested;
    }

    private static String trimToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static List<Resource__c> queryResources() {
        if (!Schema.SObjectType.Resource__c.isAccessible()) {
            return new List<Resource__c>();
        }
        return [
            SELECT Id, Name, Resource_Type__c, Summary__c, Source_URL__c,
                   City__c, Is_Crisis_Resource__c
            FROM Resource__c
            WITH USER_MODE
        ];
    }

    /** Sort: locality-specific (non-blank City) before national (blank City), then by Name asc. */
    private class ResourceComparator implements Comparator<Resource__c> {
        public Integer compare(Resource__c a, Resource__c b) {
            Boolean aNational = String.isBlank(a.City__c);
            Boolean bNational = String.isBlank(b.City__c);
            if (aNational != bNational) {
                return aNational ? 1 : -1; // national sorts after local
            }
            String an = (a.Name == null) ? '' : a.Name;
            String bn = (b.Name == null) ? '' : b.Name;
            return an.compareTo(bn);
        }
    }
}
