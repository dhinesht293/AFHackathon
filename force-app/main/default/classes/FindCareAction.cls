/**
 * FindCareAction — the "Find Care" agent action.
 *
 * Given a caregiver's (Seeker's) request, this invocable: creates a Care_Need__c,
 * runs the deterministic MatchProviders engine against it, and persists each
 * suggested provider as a Match__c (Status = 'Suggested'). It returns the created
 * careNeedId, the suggested matches, and a noMatchReason when nothing qualified.
 *
 * The matching math lives entirely in MatchProviders — this action only orchestrates
 * record creation and never scores providers itself. Bulk-safe: no SOQL/DML in loops;
 * with sharing; all DML runs in user mode so CRUD/FLS is enforced.
 */
public with sharing class FindCareAction {
    // Lifecycle statuses used by this action.
    private static final String NEED_STATUS_NEW = 'New';
    private static final String NEED_STATUS_MATCHED = 'Matched';
    private static final String MATCH_STATUS_SUGGESTED = 'Suggested';

    /**
     * Agent-facing input. Multiselect inputs (requestedDays, requestedTimeBlocks)
     * accept either a semicolon- or comma-separated list; they are normalized to
     * the semicolon-delimited form Salesforce stores multiselect picklists in.
     */
    public class Request {
        @InvocableVariable(required=true label='Seeker Contact Id')
        public Id seekerId;
        @InvocableVariable(required=true label='Care Type' description='Eldercare, Childcare, Respite, Transport, or Meals')
        public String careType;
        @InvocableVariable(required=true label='City')
        public String city;
        @InvocableVariable(label='Requested Days' description='Mon..Sun, semicolon- or comma-separated')
        public String requestedDays;
        @InvocableVariable(label='Requested Time Blocks' description='Morning;Afternoon;Evening;Overnight, semicolon- or comma-separated')
        public String requestedTimeBlocks;
        @InvocableVariable(label='Schedule')
        public String schedule;
        @InvocableVariable(label='Recurrence')
        public String recurrence;
        @InvocableVariable(label='Urgency' description='Low, Medium, High, or Crisis')
        public String urgency;
        @InvocableVariable(label='Notes')
        public String notes;
        @InvocableVariable(label='Max Results')
        public Integer maxResults;
    }

    /** A single suggested provider, mirroring MatchProviders' MatchResult plus a name. */
    public class SuggestedMatch {
        @InvocableVariable
        public Id providerId;
        @InvocableVariable
        public String providerName;
        @InvocableVariable
        public Integer score;
        @InvocableVariable
        public String reason;
    }

    /** Agent-facing output for one request. */
    public class Response {
        @InvocableVariable
        public Id careNeedId;
        @InvocableVariable
        public List<SuggestedMatch> matches;
        @InvocableVariable
        public String noMatchReason;
    }

    @InvocableMethod(label='Find Care' description='Creates a Care Need, matches verified providers, and records the suggested matches.')
    public static List<Response> findCare(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        // 1) Build + bulk-insert the Care Needs (one per request, positionally aligned).
        List<Care_Need__c> needs = new List<Care_Need__c>();
        for (Request req : requests) {
            needs.add(buildNeed(req));
        }
        Database.insert(needs, AccessLevel.USER_MODE);

        // 2) Run the matching engine for every need in one call.
        List<MatchProviders.Request> matchRequests = new List<MatchProviders.Request>();
        for (Integer i = 0; i < requests.size(); i++) {
            MatchProviders.Request mr = new MatchProviders.Request();
            mr.careNeedId = needs[i].Id;
            mr.maxResults = requests[i].maxResults;
            matchRequests.add(mr);
        }
        List<MatchProviders.Response> matchResponses = MatchProviders.matchProviders(matchRequests);

        // 3) Assemble responses, collecting Match records and needs-to-update for bulk DML.
        List<Match__c> matchesToInsert = new List<Match__c>();
        List<Care_Need__c> needsToUpdate = new List<Care_Need__c>();

        for (Integer i = 0; i < requests.size(); i++) {
            Care_Need__c need = needs[i];
            MatchProviders.Response mResp = matchResponses[i];

            Response resp = new Response();
            resp.careNeedId = need.Id;
            resp.matches = new List<SuggestedMatch>();

            List<MatchProviders.MatchResult> results =
                (mResp == null || mResp.matches == null) ? new List<MatchProviders.MatchResult>() : mResp.matches;

            if (results.isEmpty()) {
                resp.noMatchReason = (mResp == null) ? null : mResp.noMatchReason;
            } else {
                for (MatchProviders.MatchResult res : results) {
                    matchesToInsert.add(buildMatch(need.Id, res));

                    SuggestedMatch sm = new SuggestedMatch();
                    sm.providerId = res.providerId;
                    sm.score = res.score;
                    sm.reason = res.reason;
                    resp.matches.add(sm);
                }
                // Flag the need as Matched (updated in bulk below).
                needsToUpdate.add(new Care_Need__c(Id = need.Id, Status__c = NEED_STATUS_MATCHED));
            }
            responses.add(resp);
        }

        // 4) Bulk DML for the Match records and Care Need status changes.
        if (!matchesToInsert.isEmpty()) {
            Database.insert(matchesToInsert, AccessLevel.USER_MODE);
        }
        if (!needsToUpdate.isEmpty()) {
            Database.update(needsToUpdate, AccessLevel.USER_MODE);
        }

        // 5) Backfill provider names onto the response (one query, no loop DML/SOQL).
        populateProviderNames(responses);

        return responses;
    }

    private static Care_Need__c buildNeed(Request req) {
        return new Care_Need__c(
            Seeker__c = req.seekerId,
            Care_Type__c = req.careType,
            City__c = req.city,
            Urgency__c = req.urgency,
            Status__c = NEED_STATUS_NEW,
            Schedule__c = req.schedule,
            Recurrence__c = req.recurrence,
            Notes__c = req.notes,
            Requested_Day__c = normalizeMsp(req.requestedDays),
            Requested_Time_Block__c = normalizeMsp(req.requestedTimeBlocks)
        );
    }

    private static Match__c buildMatch(Id careNeedId, MatchProviders.MatchResult res) {
        return new Match__c(
            Care_Need__c = careNeedId,
            Provider_Profile__c = res.providerId,
            Score__c = res.score,
            Match_Reason__c = res.reason,
            Status__c = MATCH_STATUS_SUGGESTED
        );
    }

    /** Queries provider names once and stamps them onto every suggested match. */
    private static void populateProviderNames(List<Response> responses) {
        Set<Id> providerIds = new Set<Id>();
        for (Response resp : responses) {
            for (SuggestedMatch sm : resp.matches) {
                if (sm.providerId != null) {
                    providerIds.add(sm.providerId);
                }
            }
        }
        if (providerIds.isEmpty() || !Schema.SObjectType.Provider_Profile__c.isAccessible()) {
            return;
        }
        Map<Id, Provider_Profile__c> providersById = new Map<Id, Provider_Profile__c>([
            SELECT Id, Name
            FROM Provider_Profile__c
            WHERE Id IN :providerIds
            WITH USER_MODE
        ]);
        for (Response resp : responses) {
            for (SuggestedMatch sm : resp.matches) {
                Provider_Profile__c p = providersById.get(sm.providerId);
                if (p != null) {
                    sm.providerName = p.Name;
                }
            }
        }
    }

    /**
     * Normalizes a multiselect input to Salesforce's semicolon-delimited form.
     * Accepts either ';' or ',' as the incoming delimiter; trims and drops blanks.
     */
    private static String normalizeMsp(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        List<String> parts = new List<String>();
        for (String s : value.replace(',', ';').split(';')) {
            if (String.isNotBlank(s)) {
                parts.add(s.trim());
            }
        }
        return parts.isEmpty() ? null : String.join(parts, ';');
    }
}
