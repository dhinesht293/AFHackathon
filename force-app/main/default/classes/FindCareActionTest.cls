/**
 * FindCareActionTest — unit tests for the Find Care agent action.
 *
 * All data setup and assertions run inside System.runAs(testUser) so object CRUD
 * and field-level security are genuinely enforced (least-privilege community user,
 * not an admin). Data is built through the shared TestDataFactory.
 */
@isTest
private class FindCareActionTest {
    /** Happy path: a verified matching provider yields a Care Need + Suggested Match. */
    @isTest
    static void findCare_createsNeedAndSuggestedMatch() {
        User testUser = TestDataFactory.createTestUser();

        System.runAs(testUser) {
            Contact seeker = TestDataFactory.createContact('Lakshmi');
            Provider_Profile__c prov = TestDataFactory.createProvider(
                'Raghavan', 'Eldercare', 'Bengaluru', true,
                3, 0, 4.8,
                new List<String>{ 'Mon', 'Tue' },
                new List<String>{ 'Morning', 'Afternoon' }
            );

            FindCareAction.Request req = new FindCareAction.Request();
            req.seekerId = seeker.Id;
            req.careType = 'Eldercare';
            req.city = 'Bengaluru';
            req.requestedDays = 'Mon;Tue';
            req.requestedTimeBlocks = 'Morning;Afternoon';
            req.schedule = 'Weekday mornings';
            req.recurrence = 'Weekly';
            req.urgency = 'Medium';
            req.notes = 'Companionship and light help.';

            Test.startTest();
            List<FindCareAction.Response> responses =
                FindCareAction.findCare(new List<FindCareAction.Request>{ req });
            Test.stopTest();

            System.assertEquals(1, responses.size(), 'One response expected');
            FindCareAction.Response resp = responses[0];
            System.assertNotEquals(null, resp.careNeedId, 'careNeedId should be returned');
            System.assertEquals(null, resp.noMatchReason, 'No no-match reason on a match');
            System.assert(!resp.matches.isEmpty(), 'At least one suggested match expected');

            FindCareAction.SuggestedMatch sm = resp.matches[0];
            System.assertEquals(prov.Id, sm.providerId, 'Suggested provider Id');
            System.assertEquals('Raghavan', sm.providerName, 'Provider name backfilled');
            System.assertNotEquals(null, sm.score, 'Score populated');
            System.assert(String.isNotBlank(sm.reason), 'Reason populated');

            // Care Need persisted and flagged Matched.
            Care_Need__c need = [
                SELECT Id, Status__c, Care_Type__c, City__c, Requested_Day__c, Requested_Time_Block__c
                FROM Care_Need__c WHERE Id = :resp.careNeedId
            ];
            System.assertEquals('Matched', need.Status__c, 'Need should be Matched');
            System.assertEquals('Eldercare', need.Care_Type__c);
            System.assertEquals('Mon;Tue', need.Requested_Day__c, 'Days normalized to semicolons');

            // Match record created with Status Suggested.
            List<Match__c> matches = [
                SELECT Id, Care_Need__c, Provider_Profile__c, Score__c, Match_Reason__c, Status__c
                FROM Match__c WHERE Care_Need__c = :resp.careNeedId
            ];
            System.assertEquals(1, matches.size(), 'One Match record created');
            System.assertEquals('Suggested', matches[0].Status__c);
            System.assertEquals(prov.Id, matches[0].Provider_Profile__c);
            System.assertNotEquals(null, matches[0].Score__c);
        }
    }

    /** No verified provider for the requested type: Need created, zero Matches, reason set. */
    @isTest
    static void findCare_noMatchPopulatesReason() {
        User testUser = TestDataFactory.createTestUser();

        System.runAs(testUser) {
            Contact seeker = TestDataFactory.createContact('Selvi');
            // Only an unverified provider exists — it must never surface.
            TestDataFactory.createProvider(
                'Unverified', 'Eldercare', 'Bengaluru', false,
                3, 0, 4.0,
                new List<String>{ 'Mon' }, new List<String>{ 'Morning' }
            );

            FindCareAction.Request req = new FindCareAction.Request();
            req.seekerId = seeker.Id;
            req.careType = 'Eldercare';
            req.city = 'Bengaluru';
            req.requestedDays = 'Mon';
            req.requestedTimeBlocks = 'Morning';
            req.urgency = 'Low';

            Test.startTest();
            List<FindCareAction.Response> responses =
                FindCareAction.findCare(new List<FindCareAction.Request>{ req });
            Test.stopTest();

            FindCareAction.Response resp = responses[0];
            System.assertNotEquals(null, resp.careNeedId, 'Need still created on no match');
            System.assert(resp.matches.isEmpty(), 'No matches expected');
            System.assert(String.isNotBlank(resp.noMatchReason), 'noMatchReason populated');

            Care_Need__c need = [SELECT Status__c FROM Care_Need__c WHERE Id = :resp.careNeedId];
            System.assertEquals('New', need.Status__c, 'Need stays New when unmatched');

            System.assertEquals(
                0,
                [SELECT COUNT() FROM Match__c WHERE Care_Need__c = :resp.careNeedId],
                'No Match records on no match'
            );
        }
    }

    /** Bulk + comma-delimited input: two requests processed in one invocation. */
    @isTest
    static void findCare_bulkAndCommaDelimitedInputs() {
        User testUser = TestDataFactory.createTestUser();

        System.runAs(testUser) {
            Contact seekerA = TestDataFactory.createContact('SeekerA');
            Contact seekerB = TestDataFactory.createContact('SeekerB');
            TestDataFactory.createProvider(
                'Meena', 'Childcare', 'Bengaluru', true,
                2, 0, 4.5,
                new List<String>{ 'Sat', 'Sun' },
                new List<String>{ 'Morning' }
            );

            FindCareAction.Request reqA = new FindCareAction.Request();
            reqA.seekerId = seekerA.Id;
            reqA.careType = 'Childcare';
            reqA.city = 'Bengaluru';
            reqA.requestedDays = 'Sat,Sun'; // comma-delimited on purpose
            reqA.requestedTimeBlocks = 'Morning';
            reqA.urgency = 'Medium';

            FindCareAction.Request reqB = new FindCareAction.Request();
            reqB.seekerId = seekerB.Id;
            reqB.careType = 'Transport'; // no provider -> no match
            reqB.city = 'Bengaluru';
            reqB.urgency = 'Low';

            Test.startTest();
            List<FindCareAction.Response> responses = FindCareAction.findCare(
                new List<FindCareAction.Request>{ reqA, reqB }
            );
            Test.stopTest();

            System.assertEquals(2, responses.size(), 'Two responses for two requests');
            System.assert(!responses[0].matches.isEmpty(), 'Request A should match');
            System.assert(responses[1].matches.isEmpty(), 'Request B should not match');
            System.assert(String.isNotBlank(responses[1].noMatchReason), 'B has a no-match reason');

            Care_Need__c needA = [
                SELECT Requested_Day__c FROM Care_Need__c WHERE Id = :responses[0].careNeedId
            ];
            System.assertEquals('Sat;Sun', needA.Requested_Day__c, 'Comma input normalized to semicolons');
        }
    }

    /** Guard: null/empty input returns an empty list without DML. */
    @isTest
    static void findCare_emptyInputReturnsEmpty() {
        User testUser = TestDataFactory.createTestUser();
        System.runAs(testUser) {
            System.assert(FindCareAction.findCare(null).isEmpty(), 'null -> empty');
            System.assert(
                FindCareAction.findCare(new List<FindCareAction.Request>()).isEmpty(),
                'empty -> empty'
            );
        }
    }
}
