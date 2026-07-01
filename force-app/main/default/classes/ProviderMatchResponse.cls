/**
 * ProviderMatchResponse — provider-side accept/decline action for a suggested Match.
 *
 * Invocable called by the Agentforce Provider topic when a care Provider accepts
 * or declines a match. Deterministic state machine, no LLM math:
 *   Accept  : Match -> Accepted; Provider.Active_Match_Count += 1 (capacity);
 *             Care_Need -> Matched.
 *   Decline : Match -> Declined; capacity untouched.
 * Only a Match in Suggested/Requested may transition; any other state returns
 * success=false with a message (never throws an unhandled exception).
 *
 * Bulk-safe: one SOQL to load all Matches (with parents) WITH USER_MODE, process
 * in memory, then per-object bulk DML with AccessLevel.USER_MODE. No SOQL/DML in
 * loops. with sharing.
 */
public with sharing class ProviderMatchResponse {
    private static final String ACCEPT = 'ACCEPT';
    private static final String DECLINE = 'DECLINE';

    // States from which an Accept/Decline is a valid transition.
    private static final Set<String> OPEN_STATES = new Set<String>{ 'Suggested', 'Requested' };

    public class Request {
        @InvocableVariable(required=true label='Match Id')
        public Id matchId;
        @InvocableVariable(required=true label='Decision' description='Accept or Decline (case-insensitive).')
        public String decision;
    }

    public class Response {
        @InvocableVariable
        public Boolean success;
        @InvocableVariable
        public String status;
        @InvocableVariable
        public String message;
    }

    @InvocableMethod(
        label='Respond to Match'
        description='Provider accepts or declines a suggested match; updates match, provider capacity, and care need deterministically.'
    )
    public static List<Response> respond(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        // Collect the Match Ids we need in a single query.
        Set<Id> matchIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.matchId != null) {
                matchIds.add(req.matchId);
            }
        }

        Map<Id, Match__c> matchesById = new Map<Id, Match__c>(queryMatches(matchIds));

        // Records to persist, grouped by object type for bulk DML.
        List<Match__c> matchesToUpdate = new List<Match__c>();
        Map<Id, Provider_Profile__c> providersToUpdate = new Map<Id, Provider_Profile__c>();
        Map<Id, Care_Need__c> needsToUpdate = new Map<Id, Care_Need__c>();

        // Preserve 1:1 ordering with the incoming requests.
        for (Request req : requests) {
            responses.add(
                processRequest(req, matchesById, matchesToUpdate, providersToUpdate, needsToUpdate)
            );
        }

        // Bulk DML — one statement per object type, USER_MODE enforced.
        if (!matchesToUpdate.isEmpty()) {
            Database.update(matchesToUpdate, AccessLevel.USER_MODE);
        }
        if (!providersToUpdate.isEmpty()) {
            Database.update(providersToUpdate.values(), AccessLevel.USER_MODE);
        }
        if (!needsToUpdate.isEmpty()) {
            Database.update(needsToUpdate.values(), AccessLevel.USER_MODE);
        }

        return responses;
    }

    /**
     * Validates one request and, when valid, stages the record mutations into the
     * shared update collections. Returns the per-request Response either way.
     */
    private static Response processRequest(
        Request req,
        Map<Id, Match__c> matchesById,
        List<Match__c> matchesToUpdate,
        Map<Id, Provider_Profile__c> providersToUpdate,
        Map<Id, Care_Need__c> needsToUpdate
    ) {
        Response resp = new Response();
        resp.success = false;

        if (req == null || req.matchId == null) {
            resp.message = 'No match specified.';
            return resp;
        }

        String decision = req.decision == null ? '' : req.decision.trim().toUpperCase();
        if (decision != ACCEPT && decision != DECLINE) {
            resp.message = 'Decision must be "Accept" or "Decline".';
            return resp;
        }

        Match__c m = matchesById.get(req.matchId);
        if (m == null) {
            resp.message = 'Match not found or not accessible.';
            return resp;
        }

        resp.status = m.Status__c;
        if (!OPEN_STATES.contains(m.Status__c)) {
            resp.message = 'This match is already "' + m.Status__c
                + '" and can no longer be ' + (decision == ACCEPT ? 'accepted' : 'declined') + '.';
            return resp;
        }

        if (decision == ACCEPT) {
            m.Status__c = 'Accepted';
            matchesToUpdate.add(m);

            // Increment provider capacity (null-safe). Dedupe so multiple accepts
            // for the same provider in one call each count.
            Provider_Profile__c prov = providersToUpdate.get(m.Provider_Profile__c);
            if (prov == null) {
                Decimal current = m.Provider_Profile__r.Active_Match_Count__c == null
                    ? 0
                    : m.Provider_Profile__r.Active_Match_Count__c;
                prov = new Provider_Profile__c(
                    Id = m.Provider_Profile__c,
                    Active_Match_Count__c = current
                );
                providersToUpdate.put(prov.Id, prov);
            }
            prov.Active_Match_Count__c = prov.Active_Match_Count__c + 1;

            // Advance the care need to Matched.
            if (m.Care_Need__c != null && !needsToUpdate.containsKey(m.Care_Need__c)) {
                needsToUpdate.put(
                    m.Care_Need__c,
                    new Care_Need__c(Id = m.Care_Need__c, Status__c = 'Matched')
                );
            }

            resp.success = true;
            resp.status = 'Accepted';
            resp.message = 'Match accepted. The seeker has been notified.';
        } else {
            m.Status__c = 'Declined';
            matchesToUpdate.add(m);

            resp.success = true;
            resp.status = 'Declined';
            resp.message = 'Match declined. No capacity was reserved.';
        }

        return resp;
    }

    private static List<Match__c> queryMatches(Set<Id> ids) {
        if (ids.isEmpty() || !Schema.SObjectType.Match__c.isAccessible()) {
            return new List<Match__c>();
        }
        return [
            SELECT Id, Status__c, Care_Need__c, Provider_Profile__c,
                   Provider_Profile__r.Active_Match_Count__c
            FROM Match__c
            WHERE Id IN :ids
            WITH USER_MODE
        ];
    }
}
