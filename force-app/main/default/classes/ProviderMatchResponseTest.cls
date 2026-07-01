/**
 * ProviderMatchResponseTest — covers the provider accept/decline state machine.
 *
 * All data setup and assertions run inside System.runAs(testUser) so object CRUD
 * and FLS are enforced as they would be for a real least-privilege community user.
 * Match__c has no factory method (by design) — records are built inline here.
 */
@isTest
private class ProviderMatchResponseTest {
    /** Helper: build+insert a Match in a given status for a need/provider pair. */
    private static Match__c newMatch(Id needId, Id providerId, String status) {
        Match__c m = new Match__c(
            Care_Need__c = needId,
            Provider_Profile__c = providerId,
            Status__c = status,
            Score__c = 88
        );
        insert m;
        return m;
    }

    private static ProviderMatchResponse.Request req(Id matchId, String decision) {
        ProviderMatchResponse.Request r = new ProviderMatchResponse.Request();
        r.matchId = matchId;
        r.decision = decision;
        return r;
    }

    @isTest
    static void acceptAdvancesMatchProviderAndNeed() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed(
                'Eldercare', 'Bengaluru', new List<String>{ 'Mon' }, new List<String>{ 'Morning' }
            );
            Provider_Profile__c prov = TestDataFactory.createProvider(
                'Prov A', 'Eldercare', 'Bengaluru', true, 3, 1, 4.8,
                new List<String>{ 'Mon' }, new List<String>{ 'Morning' }
            );
            Match__c m = newMatch(need.Id, prov.Id, 'Suggested');

            Test.startTest();
            List<ProviderMatchResponse.Response> res = ProviderMatchResponse.respond(
                new List<ProviderMatchResponse.Request>{ req(m.Id, 'Accept') }
            );
            Test.stopTest();

            System.assertEquals(1, res.size(), 'One response expected');
            System.assertEquals(true, res[0].success, 'Accept should succeed');
            System.assertEquals('Accepted', res[0].status, 'Status should be Accepted');

            Match__c reloaded = [SELECT Status__c FROM Match__c WHERE Id = :m.Id];
            System.assertEquals('Accepted', reloaded.Status__c, 'Match -> Accepted');

            Provider_Profile__c pAfter = [
                SELECT Active_Match_Count__c FROM Provider_Profile__c WHERE Id = :prov.Id
            ];
            System.assertEquals(2, pAfter.Active_Match_Count__c, 'Active count incremented 1 -> 2');

            Care_Need__c nAfter = [SELECT Status__c FROM Care_Need__c WHERE Id = :need.Id];
            System.assertEquals('Matched', nAfter.Status__c, 'Care Need -> Matched');
        }
    }

    @isTest
    static void acceptTreatsNullActiveCountAsZero() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed(
                'Eldercare', 'Bengaluru', new List<String>{ 'Mon' }, new List<String>{ 'Morning' }
            );
            // Null active count -> should be treated as 0, then become 1.
            Provider_Profile__c prov = TestDataFactory.createProvider(
                'Prov Null', 'Eldercare', 'Bengaluru', true, 3, null, 4.5,
                new List<String>{ 'Mon' }, new List<String>{ 'Morning' }
            );
            Match__c m = newMatch(need.Id, prov.Id, 'Requested');

            Test.startTest();
            List<ProviderMatchResponse.Response> res = ProviderMatchResponse.respond(
                new List<ProviderMatchResponse.Request>{ req(m.Id, 'accept') } // case-insensitive
            );
            Test.stopTest();

            System.assertEquals(true, res[0].success, 'Accept from Requested should succeed');
            Provider_Profile__c pAfter = [
                SELECT Active_Match_Count__c FROM Provider_Profile__c WHERE Id = :prov.Id
            ];
            System.assertEquals(1, pAfter.Active_Match_Count__c, 'null active count treated as 0 then +1');
        }
    }

    @isTest
    static void declineLeavesCapacityUnchanged() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed(
                'Eldercare', 'Bengaluru', new List<String>{ 'Mon' }, new List<String>{ 'Morning' }
            );
            Provider_Profile__c prov = TestDataFactory.createProvider(
                'Prov B', 'Eldercare', 'Bengaluru', true, 3, 2, 4.2,
                new List<String>{ 'Mon' }, new List<String>{ 'Morning' }
            );
            Match__c m = newMatch(need.Id, prov.Id, 'Suggested');

            Test.startTest();
            List<ProviderMatchResponse.Response> res = ProviderMatchResponse.respond(
                new List<ProviderMatchResponse.Request>{ req(m.Id, 'Decline') }
            );
            Test.stopTest();

            System.assertEquals(true, res[0].success, 'Decline should succeed');
            System.assertEquals('Declined', res[0].status, 'Status should be Declined');

            Match__c reloaded = [SELECT Status__c FROM Match__c WHERE Id = :m.Id];
            System.assertEquals('Declined', reloaded.Status__c, 'Match -> Declined');

            Provider_Profile__c pAfter = [
                SELECT Active_Match_Count__c FROM Provider_Profile__c WHERE Id = :prov.Id
            ];
            System.assertEquals(2, pAfter.Active_Match_Count__c, 'Capacity unchanged on decline');

            Care_Need__c nAfter = [SELECT Status__c FROM Care_Need__c WHERE Id = :need.Id];
            System.assertEquals('New', nAfter.Status__c, 'Care Need untouched on decline');
        }
    }

    @isTest
    static void invalidTransitionReturnsFailureNoException() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed(
                'Eldercare', 'Bengaluru', new List<String>{ 'Mon' }, new List<String>{ 'Morning' }
            );
            Provider_Profile__c prov = TestDataFactory.createProvider(
                'Prov C', 'Eldercare', 'Bengaluru', true, 3, 1, 4.0,
                new List<String>{ 'Mon' }, new List<String>{ 'Morning' }
            );
            // Already Accepted — cannot be re-accepted.
            Match__c m = newMatch(need.Id, prov.Id, 'Accepted');

            Test.startTest();
            List<ProviderMatchResponse.Response> res = ProviderMatchResponse.respond(
                new List<ProviderMatchResponse.Request>{ req(m.Id, 'Accept') }
            );
            Test.stopTest();

            System.assertEquals(1, res.size(), 'One response expected');
            System.assertEquals(false, res[0].success, 'Re-accept must fail');
            System.assertEquals('Accepted', res[0].status, 'Reports current status');
            System.assertNotEquals(null, res[0].message, 'A message should be present');

            Provider_Profile__c pAfter = [
                SELECT Active_Match_Count__c FROM Provider_Profile__c WHERE Id = :prov.Id
            ];
            System.assertEquals(1, pAfter.Active_Match_Count__c, 'No capacity change on invalid transition');
        }
    }

    @isTest
    static void badInputsAndBulkAreHandled() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed(
                'Eldercare', 'Bengaluru', new List<String>{ 'Mon' }, new List<String>{ 'Morning' }
            );
            Provider_Profile__c prov = TestDataFactory.createProvider(
                'Prov D', 'Eldercare', 'Bengaluru', true, 5, 0, 3.9,
                new List<String>{ 'Mon' }, new List<String>{ 'Morning' }
            );
            Match__c ok = newMatch(need.Id, prov.Id, 'Suggested');

            List<ProviderMatchResponse.Request> reqs = new List<ProviderMatchResponse.Request>{
                req(ok.Id, 'Accept'),          // valid
                req(null, 'Accept'),           // missing id
                req(ok.Id, 'Maybe')            // invalid decision
            };

            Test.startTest();
            List<ProviderMatchResponse.Response> res = ProviderMatchResponse.respond(reqs);
            // null / empty inputs are no-ops that must not throw.
            List<ProviderMatchResponse.Response> emptyRes = ProviderMatchResponse.respond(
                new List<ProviderMatchResponse.Request>()
            );
            List<ProviderMatchResponse.Response> nullRes = ProviderMatchResponse.respond(null);
            Test.stopTest();

            System.assertEquals(3, res.size(), 'One response per request, order preserved');
            System.assertEquals(true, res[0].success, 'First (valid) succeeds');
            System.assertEquals(false, res[1].success, 'Missing id fails');
            System.assertEquals(false, res[2].success, 'Invalid decision fails');
            System.assertEquals(true, emptyRes.isEmpty(), 'Empty input -> empty output');
            System.assertEquals(true, nullRes.isEmpty(), 'Null input -> empty output');
        }
    }
}
