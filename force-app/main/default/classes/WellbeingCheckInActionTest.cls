/**
 * WellbeingCheckInActionTest — unit tests for the crisis-guardrail action.
 *
 * All setup + assertions run inside System.runAs(testUser) so object CRUD and
 * field-level security are enforced exactly as a community user would hit them.
 * Covers the crisis, moderate, and low paths plus the no-resource fallback and
 * a bulk mix, targeting >=90% coverage of WellbeingCheckInAction.
 */
@isTest
private class WellbeingCheckInActionTest {
    private static WellbeingCheckInAction.Request buildRequest(
        Id contactId, String signals, Decimal score, Boolean isCrisis
    ) {
        WellbeingCheckInAction.Request req = new WellbeingCheckInAction.Request();
        req.contactId = contactId;
        req.strainSignals = signals;
        req.strainScore = score;
        req.isCrisis = isCrisis;
        return req;
    }

    @isTest
    static void crisisPathCreatesCaseAndReturnsResource() {
        User testUser = TestDataFactory.createTestUser();

        System.runAs(testUser) {
            Contact caregiver = TestDataFactory.createContact('Caregiver');
            insert new Resource__c(
                Name = 'CareCircle Helpline',
                Resource_Type__c = 'Crisis Line',
                Summary__c = 'A 24/7 confidential support line.',
                Source_URL__c = 'https://example.org/helpline',
                Is_Crisis_Resource__c = true
            );

            WellbeingCheckInAction.Request req = buildRequest(
                caregiver.Id, 'Expressed feeling overwhelmed and hopeless', 9, true
            );

            Test.startTest();
            List<WellbeingCheckInAction.Response> resps =
                WellbeingCheckInAction.logCheckIn(new List<WellbeingCheckInAction.Request>{ req });
            Test.stopTest();

            System.assertEquals(1, resps.size(), 'one response expected');
            WellbeingCheckInAction.Response resp = resps[0];
            System.assertEquals('Case_Created', resp.escalationStatus, 'crisis should escalate to a Case');
            System.assertNotEquals(null, resp.checkInId, 'check-in should be created');
            System.assertNotEquals(null, resp.caseId, 'a Case should be created for the handoff');
            System.assert(resp.crisisResource != null && resp.crisisResource.contains('CareCircle Helpline'),
                'crisis resource should carry the real helpline name');
            System.assert(resp.crisisResource.contains('https://example.org/helpline'),
                'crisis resource should carry the source URL');

            Wellbeing_CheckIn__c ci = [
                SELECT Escalation_Status__c, Case__c, Score__c, Strain_Signals__c
                FROM Wellbeing_CheckIn__c WHERE Id = :resp.checkInId
            ];
            System.assertEquals('Case_Created', ci.Escalation_Status__c, 'stored status matches');
            System.assertEquals(resp.caseId, ci.Case__c, 'check-in should link the Case');
            System.assertEquals(9, ci.Score__c, 'score persisted');

            Case created = [SELECT Status, Origin, ContactId FROM Case WHERE Id = :resp.caseId];
            System.assertEquals('New', created.Status, 'Case status New');
            System.assertEquals('Web', created.Origin, 'Case origin Web');
            System.assertEquals(caregiver.Id, created.ContactId, 'Case linked to caregiver');
        }
    }

    @isTest
    static void highScoreWithoutCrisisFlagStillEscalates() {
        User testUser = TestDataFactory.createTestUser();

        System.runAs(testUser) {
            Contact caregiver = TestDataFactory.createContact('HighScore');
            // No crisis Resource configured -> exercises the safe fallback message.

            WellbeingCheckInAction.Request req = buildRequest(
                caregiver.Id, 'Sustained exhaustion', 8, false
            );

            Test.startTest();
            List<WellbeingCheckInAction.Response> resps =
                WellbeingCheckInAction.logCheckIn(new List<WellbeingCheckInAction.Request>{ req });
            Test.stopTest();

            WellbeingCheckInAction.Response resp = resps[0];
            System.assertEquals('Case_Created', resp.escalationStatus, 'score >= 8 escalates without the crisis flag');
            System.assertNotEquals(null, resp.caseId, 'Case created for high score');
            System.assertNotEquals(null, resp.crisisResource, 'fallback message returned when no crisis resource exists');
        }
    }

    @isTest
    static void moderatePathOffersResourcesNoCase() {
        User testUser = TestDataFactory.createTestUser();

        System.runAs(testUser) {
            Contact caregiver = TestDataFactory.createContact('Moderate');

            WellbeingCheckInAction.Request req = buildRequest(
                caregiver.Id, 'Mentioned being tired and stretched thin', 5, false
            );

            Test.startTest();
            List<WellbeingCheckInAction.Response> resps =
                WellbeingCheckInAction.logCheckIn(new List<WellbeingCheckInAction.Request>{ req });
            Test.stopTest();

            WellbeingCheckInAction.Response resp = resps[0];
            System.assertEquals('Resources_Offered', resp.escalationStatus, 'moderate strain offers resources');
            System.assertEquals(null, resp.caseId, 'no Case for moderate strain');
            System.assertEquals(null, resp.crisisResource, 'no crisis resource for non-crisis path');
            System.assertNotEquals(null, resp.checkInId, 'check-in still recorded');

            System.assertEquals(0, [SELECT COUNT() FROM Case], 'no Case should exist');
        }
    }

    @isTest
    static void lowPathRecordsNone() {
        User testUser = TestDataFactory.createTestUser();

        System.runAs(testUser) {
            Contact caregiver = TestDataFactory.createContact('Low');

            WellbeingCheckInAction.Request req = buildRequest(
                caregiver.Id, 'Routine check-in, doing fine', 1, false
            );

            Test.startTest();
            List<WellbeingCheckInAction.Response> resps =
                WellbeingCheckInAction.logCheckIn(new List<WellbeingCheckInAction.Request>{ req });
            Test.stopTest();

            WellbeingCheckInAction.Response resp = resps[0];
            System.assertEquals('None', resp.escalationStatus, 'low strain records None');
            System.assertEquals(null, resp.caseId, 'no Case for low strain');
            System.assertEquals(null, resp.crisisResource, 'no crisis resource for low path');

            Wellbeing_CheckIn__c ci = [
                SELECT Escalation_Status__c FROM Wellbeing_CheckIn__c WHERE Id = :resp.checkInId
            ];
            System.assertEquals('None', ci.Escalation_Status__c, 'stored status None');
        }
    }

    @isTest
    static void bulkMixHandlesAllPaths() {
        User testUser = TestDataFactory.createTestUser();

        System.runAs(testUser) {
            Contact c1 = TestDataFactory.createContact('BulkCrisis');
            Contact c2 = TestDataFactory.createContact('BulkModerate');
            Contact c3 = TestDataFactory.createContact('BulkLow');
            insert new Resource__c(
                Name = 'Bulk Helpline',
                Resource_Type__c = 'Crisis Line',
                Summary__c = 'Support line.',
                Source_URL__c = 'https://example.org/bulk',
                Is_Crisis_Resource__c = true
            );

            List<WellbeingCheckInAction.Request> reqs = new List<WellbeingCheckInAction.Request>{
                buildRequest(c1.Id, 'crisis language', 10, true),
                buildRequest(c2.Id, 'moderate strain', 4, false),
                buildRequest(c3.Id, 'fine', 0, false)
            };

            Test.startTest();
            List<WellbeingCheckInAction.Response> resps = WellbeingCheckInAction.logCheckIn(reqs);
            Test.stopTest();

            System.assertEquals(3, resps.size(), 'one response per request, positionally aligned');
            System.assertEquals('Case_Created', resps[0].escalationStatus, 'row 0 crisis');
            System.assertNotEquals(null, resps[0].caseId, 'row 0 has a Case');
            System.assertEquals('Resources_Offered', resps[1].escalationStatus, 'row 1 moderate');
            System.assertEquals(null, resps[1].caseId, 'row 1 no Case');
            System.assertEquals('None', resps[2].escalationStatus, 'row 2 low');
            System.assertEquals(null, resps[2].caseId, 'row 2 no Case');

            System.assertEquals(1, [SELECT COUNT() FROM Case], 'exactly one Case from the crisis row');
            System.assertEquals(3, [SELECT COUNT() FROM Wellbeing_CheckIn__c], 'all three check-ins recorded');
        }
    }

    @isTest
    static void nullAndEmptyInputsAreSafe() {
        User testUser = TestDataFactory.createTestUser();

        System.runAs(testUser) {
            Test.startTest();
            List<WellbeingCheckInAction.Response> nullResp = WellbeingCheckInAction.logCheckIn(null);
            List<WellbeingCheckInAction.Response> emptyResp =
                WellbeingCheckInAction.logCheckIn(new List<WellbeingCheckInAction.Request>());
            Test.stopTest();

            System.assertEquals(0, nullResp.size(), 'null input returns empty list');
            System.assertEquals(0, emptyResp.size(), 'empty input returns empty list');
        }
    }
}
