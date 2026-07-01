/**
 * FindResourcesActionTest — unit tests for the grounded resource-lookup action.
 *
 * All setup + assertions run inside System.runAs(testUser) so object CRUD and FLS
 * are enforced as a real community user (Standard User + CareCircle permission set).
 * Resource__c has no TestDataFactory builder, so records are created here directly.
 */
@isTest
private class FindResourcesActionTest {
    private static Resource__c buildResource(
        String name, String type, String city, Boolean isCrisis
    ) {
        return new Resource__c(
            Name = name,
            Resource_Type__c = type,
            City__c = city,
            Summary__c = name + ' summary.',
            Source_URL__c = 'https://example.org/' + EncodingUtil.urlEncode(name, 'UTF-8'),
            Is_Crisis_Resource__c = isCrisis
        );
    }

    @isTest
    static void filterByTypeReturnsOnlyThatType() {
        User testUser = TestDataFactory.createTestUser();
        System.runAs(testUser) {
            insert new List<Resource__c>{
                buildResource('Caregiver Circle', 'Support Group', 'Bengaluru', false),
                buildResource('Home Nursing Co', 'Local Service', 'Bengaluru', false),
                buildResource('Elder Care Scheme', 'Benefit/Scheme', null, false)
            };

            FindResourcesAction.Request req = new FindResourcesAction.Request();
            req.resourceType = 'Support Group';

            Test.startTest();
            List<FindResourcesAction.Response> responses =
                FindResourcesAction.findResources(new List<FindResourcesAction.Request>{ req });
            Test.stopTest();

            System.assertEquals(1, responses.size(), 'One response per request');
            FindResourcesAction.Response resp = responses[0];
            System.assertEquals(1, resp.resultCount, 'Only the Support Group should match');
            System.assertEquals(1, resp.results.size(), 'Result list should match count');
            System.assertEquals('Support Group', resp.results[0].resourceType, 'Type filter honored');
            System.assertEquals('Caregiver Circle', resp.results[0].name, 'Correct record returned');
            System.assertNotEquals(null, resp.results[0].sourceUrl, 'Citation URL surfaced');
            System.assertEquals(null, resp.noResultsMessage, 'No message when results exist');
        }
    }

    @isTest
    static void cityFilterReturnsLocalThenNational() {
        User testUser = TestDataFactory.createTestUser();
        System.runAs(testUser) {
            insert new List<Resource__c>{
                // National (blank city) — should appear AFTER local ones.
                buildResource('National Helpline', 'Support Group', null, false),
                // Local to Bengaluru.
                buildResource('Bengaluru Zeta Group', 'Support Group', 'Bengaluru', false),
                buildResource('Bengaluru Alpha Group', 'Support Group', 'Bengaluru', false),
                // Other city — must be excluded.
                buildResource('Chennai Group', 'Support Group', 'Chennai', false)
            };

            FindResourcesAction.Request req = new FindResourcesAction.Request();
            req.resourceType = 'Support Group';
            req.city = 'Bengaluru';

            Test.startTest();
            List<FindResourcesAction.Response> responses =
                FindResourcesAction.findResources(new List<FindResourcesAction.Request>{ req });
            Test.stopTest();

            FindResourcesAction.Response resp = responses[0];
            System.assertEquals(3, resp.resultCount, 'Two local + one national, Chennai excluded');
            // Local first, ordered by Name; national last.
            System.assertEquals('Bengaluru Alpha Group', resp.results[0].name, 'Local, alpha by name');
            System.assertEquals('Bengaluru Zeta Group', resp.results[1].name, 'Local, then zeta');
            System.assertEquals('National Helpline', resp.results[2].name, 'National sorts last');
        }
    }

    @isTest
    static void noMatchReturnsEmptyWithMessage() {
        User testUser = TestDataFactory.createTestUser();
        System.runAs(testUser) {
            insert new List<Resource__c>{
                buildResource('Some Benefit', 'Benefit/Scheme', 'Bengaluru', false)
            };

            FindResourcesAction.Request req = new FindResourcesAction.Request();
            req.resourceType = 'Crisis Line';
            req.city = 'Bengaluru';

            Test.startTest();
            List<FindResourcesAction.Response> responses =
                FindResourcesAction.findResources(new List<FindResourcesAction.Request>{ req });
            Test.stopTest();

            FindResourcesAction.Response resp = responses[0];
            System.assertEquals(0, resp.resultCount, 'No Crisis Line on file');
            System.assertEquals(true, resp.results.isEmpty(), 'Empty result list');
            System.assertNotEquals(null, resp.noResultsMessage, 'noResultsMessage populated');
            System.assert(
                resp.noResultsMessage.contains('Crisis Line'),
                'Message names the requested type'
            );
        }
    }

    @isTest
    static void maxResultsCapRespected() {
        User testUser = TestDataFactory.createTestUser();
        System.runAs(testUser) {
            List<Resource__c> toInsert = new List<Resource__c>();
            for (Integer i = 0; i < 8; i++) {
                toInsert.add(buildResource('Group ' + i, 'Support Group', 'Bengaluru', false));
            }
            insert toInsert;

            FindResourcesAction.Request req = new FindResourcesAction.Request();
            req.resourceType = 'Support Group';
            req.city = 'Bengaluru';
            req.maxResults = 3;

            Test.startTest();
            List<FindResourcesAction.Response> responses =
                FindResourcesAction.findResources(new List<FindResourcesAction.Request>{ req });
            Test.stopTest();

            FindResourcesAction.Response resp = responses[0];
            System.assertEquals(3, resp.resultCount, 'Cap of 3 honored');
            System.assertEquals(3, resp.results.size(), 'Result list capped');
        }
    }

    @isTest
    static void defaultCapAndNoCityReturnsAllOfType() {
        User testUser = TestDataFactory.createTestUser();
        System.runAs(testUser) {
            List<Resource__c> toInsert = new List<Resource__c>();
            for (Integer i = 0; i < 7; i++) {
                // Mix of cities; no city filter => all of the type, capped at default 5.
                String city = (Math.mod(i, 2) == 0) ? 'Bengaluru' : null;
                toInsert.add(buildResource('Svc ' + i, 'Local Service', city, false));
            }
            insert toInsert;

            FindResourcesAction.Request req = new FindResourcesAction.Request();
            req.resourceType = 'Local Service';
            // no city, no maxResults => default cap of 5

            Test.startTest();
            List<FindResourcesAction.Response> responses =
                FindResourcesAction.findResources(new List<FindResourcesAction.Request>{ req });
            Test.stopTest();

            FindResourcesAction.Response resp = responses[0];
            System.assertEquals(5, resp.resultCount, 'Default cap of 5 applied with no city filter');
        }
    }

    @isTest
    static void crisisFlagAndBulkRequestsHandled() {
        User testUser = TestDataFactory.createTestUser();
        System.runAs(testUser) {
            insert new List<Resource__c>{
                buildResource('Suicide Prevention Line', 'Crisis Line', null, true),
                buildResource('Local Support', 'Support Group', 'Bengaluru', false)
            };

            FindResourcesAction.Request crisisReq = new FindResourcesAction.Request();
            crisisReq.resourceType = 'Crisis Line';

            FindResourcesAction.Request groupReq = new FindResourcesAction.Request();
            groupReq.resourceType = 'Support Group';
            groupReq.city = 'Bengaluru';

            Test.startTest();
            List<FindResourcesAction.Response> responses = FindResourcesAction.findResources(
                new List<FindResourcesAction.Request>{ crisisReq, groupReq }
            );
            Test.stopTest();

            System.assertEquals(2, responses.size(), 'One response per request (bulk-safe)');
            System.assertEquals(1, responses[0].resultCount, 'Crisis Line found');
            System.assertEquals(true, responses[0].results[0].isCrisisResource, 'Crisis flag surfaced');
            System.assertEquals(1, responses[1].resultCount, 'Support Group found for city');
            System.assertEquals(false, responses[1].results[0].isCrisisResource, 'Non-crisis flag correct');
        }
    }

    @isTest
    static void nullAndEmptyRequestsAreSafe() {
        User testUser = TestDataFactory.createTestUser();
        System.runAs(testUser) {
            Test.startTest();
            List<FindResourcesAction.Response> nullResp = FindResourcesAction.findResources(null);
            List<FindResourcesAction.Response> emptyResp =
                FindResourcesAction.findResources(new List<FindResourcesAction.Request>());
            Test.stopTest();

            System.assertEquals(true, nullResp.isEmpty(), 'Null input yields empty response list');
            System.assertEquals(true, emptyResp.isEmpty(), 'Empty input yields empty response list');
        }
    }
}
