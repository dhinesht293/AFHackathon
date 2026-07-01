/**
 * WellbeingCheckInAction — the well-being + crisis-guardrail agent action.
 *
 * The agent calls this when it detects caregiver strain/burnout signals. This action
 * ONLY records and routes — it never diagnoses, counsels, or generates advice text.
 * It logs a Wellbeing_CheckIn__c, decides an escalation outcome, and on a crisis signal
 * performs a human handoff (creates a Case routed to the 'CareCircle Support' queue) and
 * returns a REAL helpline drawn from Resource__c (never a fabricated one).
 *
 * Escalation thresholds (deterministic): isCrisis == true OR score >= 8 -> Case_Created;
 * else score >= 4 -> Resources_Offered; else -> None.
 *
 * Bulk-safe: crisis Resource + support Queue are queried once up front (outside any loop);
 * Cases and CheckIns are built in lists and bulk-inserted (Cases first so their Ids can be
 * stamped onto the CheckIns). No SOQL/DML in loops; with sharing; USER_MODE DML.
 */
public with sharing class WellbeingCheckInAction {
    // Escalation thresholds on the 0-10 strain score.
    private static final Decimal CRISIS_SCORE = 8;
    private static final Decimal MODERATE_SCORE = 4;

    // Escalation outcomes (must match the restricted picklist on Escalation_Status__c).
    private static final String ESC_NONE = 'None';
    private static final String ESC_RESOURCES = 'Resources_Offered';
    private static final String ESC_CASE = 'Case_Created';

    // Support queue lookup values.
    private static final String QUEUE_NAME = 'CareCircle Support';
    private static final String QUEUE_DEVNAME = 'CareCircle_Support';

    // Safe fallback when no crisis Resource is configured — factual, non-clinical.
    private static final String FALLBACK_CRISIS_MESSAGE =
        'A member of the CareCircle support team has been notified and will reach out. ' +
        'If you or someone else is in immediate danger, please contact your local emergency services right away.';

    /** Agent-facing input for one caregiver check-in. */
    public class Request {
        @InvocableVariable(required=true label='Caregiver Contact Id')
        public Id contactId;
        @InvocableVariable(label='Strain Signals' description='Non-clinical cues the agent observed')
        public String strainSignals;
        @InvocableVariable(label='Strain Score' description='0-10 rough strain indicator, not a diagnosis')
        public Decimal strainScore;
        @InvocableVariable(label='Is Crisis' description='True when crisis language was detected')
        public Boolean isCrisis;
    }

    /** Agent-facing output for one check-in. */
    public class Response {
        @InvocableVariable
        public Id checkInId;
        @InvocableVariable
        public String escalationStatus;
        @InvocableVariable
        public Id caseId;
        @InvocableVariable
        public String crisisResource;
    }

    @InvocableMethod(
        label='Well-being Check-In'
        description='Records a caregiver well-being check-in and, on a crisis signal, hands off to a human and returns a real helpline. Never diagnoses or counsels.'
    )
    public static List<Response> logCheckIn(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        // Query shared resources ONCE (bulk-safe): the crisis helpline + the support queue.
        Resource__c crisisResource = queryCrisisResource();
        Id queueId = querySupportQueueId();
        String crisisResourceText = buildCrisisResourceText(crisisResource);
        Boolean queueMissing = (queueId == null);

        // Pass 1: decide outcomes; build Cases for the crisis rows (positionally tracked).
        List<Case> casesToInsert = new List<Case>();
        List<Integer> caseRowIndex = new List<Integer>();
        String[] outcomes = new String[requests.size()];

        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            String outcome = decideOutcome(req);
            outcomes[i] = outcome;

            if (outcome == ESC_CASE) {
                casesToInsert.add(buildCase(req, queueId, queueMissing));
                caseRowIndex.add(i);
            }
        }

        // Bulk-insert Cases first so the new Case Ids can be stamped onto the CheckIns.
        if (!casesToInsert.isEmpty()) {
            Database.insert(casesToInsert, AccessLevel.USER_MODE);
        }

        // Pass 2: build the CheckIns, linking each crisis row's Case.
        List<Wellbeing_CheckIn__c> checkInsToInsert = new List<Wellbeing_CheckIn__c>();
        Map<Integer, Case> caseByRow = new Map<Integer, Case>();
        for (Integer k = 0; k < caseRowIndex.size(); k++) {
            caseByRow.put(caseRowIndex[k], casesToInsert[k]);
        }

        for (Integer i = 0; i < requests.size(); i++) {
            Case linkedCase = caseByRow.get(i);
            checkInsToInsert.add(buildCheckIn(requests[i], outcomes[i], linkedCase));
        }
        Database.insert(checkInsToInsert, AccessLevel.USER_MODE);

        // Pass 3: assemble responses (no DML/SOQL in this loop).
        for (Integer i = 0; i < requests.size(); i++) {
            Response resp = new Response();
            resp.checkInId = checkInsToInsert[i].Id;
            resp.escalationStatus = outcomes[i];

            Case linkedCase = caseByRow.get(i);
            if (linkedCase != null) {
                resp.caseId = linkedCase.Id;
                resp.crisisResource = crisisResourceText;
                if (queueMissing) {
                    resp.crisisResource += ' [Setup note: support queue "'
                        + QUEUE_NAME + '" not found; Case left with default owner for the integrator to route.]';
                }
            }
            responses.add(resp);
        }
        return responses;
    }

    /** Deterministic escalation decision. */
    private static String decideOutcome(Request req) {
        Boolean crisis = (req.isCrisis == true);
        Decimal score = (req.strainScore == null) ? 0 : req.strainScore;
        if (crisis || score >= CRISIS_SCORE) {
            return ESC_CASE;
        }
        if (score >= MODERATE_SCORE) {
            return ESC_RESOURCES;
        }
        return ESC_NONE;
    }

    private static Wellbeing_CheckIn__c buildCheckIn(Request req, String outcome, Case linkedCase) {
        Wellbeing_CheckIn__c ci = new Wellbeing_CheckIn__c(
            Contact__c = req.contactId,
            Strain_Signals__c = req.strainSignals,
            Score__c = req.strainScore,
            Escalation_Status__c = outcome
        );
        if (linkedCase != null) {
            ci.Case__c = linkedCase.Id;
        }
        return ci;
    }

    /** Builds the human-handoff Case. Factual subject/description only — no clinical language. */
    private static Case buildCase(Request req, Id queueId, Boolean queueMissing) {
        Case c = new Case(
            Subject = 'CareCircle well-being escalation',
            Description = 'Automated well-being check-in flagged elevated caregiver strain and was escalated for human follow-up. '
                + 'Detected signals: ' + (String.isBlank(req.strainSignals) ? 'not provided' : req.strainSignals)
                + ' | Strain score: ' + (req.strainScore == null ? 'not provided' : String.valueOf(req.strainScore)) + '/10.',
            Status = 'New',
            Origin = 'Web',
            ContactId = req.contactId
        );
        // Route to the support queue when it exists; otherwise leave default owner for the integrator.
        if (!queueMissing) {
            c.OwnerId = queueId;
        }
        return c;
    }

    /** First crisis-flagged Resource, or null. One query, no loop. */
    private static Resource__c queryCrisisResource() {
        if (!Schema.SObjectType.Resource__c.isAccessible()) {
            return null;
        }
        List<Resource__c> rows = [
            SELECT Id, Name, Summary__c, Source_URL__c
            FROM Resource__c
            WHERE Is_Crisis_Resource__c = true
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /** Id of the 'CareCircle Support' queue over Case, or null when absent. */
    private static Id querySupportQueueId() {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
              AND (DeveloperName = :QUEUE_DEVNAME OR Name = :QUEUE_NAME)
            LIMIT 1
        ];
        return queues.isEmpty() ? null : queues[0].Id;
    }

    /** Factual helpline text (name; summary; url), or a safe fallback. Never clinical advice. */
    private static String buildCrisisResourceText(Resource__c r) {
        if (r == null) {
            return FALLBACK_CRISIS_MESSAGE;
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(r.Name)) {
            parts.add(r.Name);
        }
        if (String.isNotBlank(r.Summary__c)) {
            parts.add(r.Summary__c);
        }
        if (String.isNotBlank(r.Source_URL__c)) {
            parts.add(r.Source_URL__c);
        }
        return parts.isEmpty() ? FALLBACK_CRISIS_MESSAGE : String.join(parts, ' — ');
    }
}
