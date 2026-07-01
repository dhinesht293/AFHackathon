@isTest
private class MatchProvidersTest {
    // Bengaluru reference point for geo tests
    private static final Double BLR_LAT = 12.9716;
    private static final Double BLR_LNG = 77.5946;

    // Row 1: verified, offers type, in city, available -> returned with score>0 and reason
    @isTest
    static void returnsMatchingVerifiedProvider() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed('Eldercare', 'Bengaluru',
                new List<String>{'Tue'}, new List<String>{'Afternoon'});
            TestDataFactory.createProvider('Selvi', 'Eldercare;Respite', 'Bengaluru', true, 3, 0, 4.8,
                new List<String>{'Tue','Wed'}, new List<String>{'Afternoon'});

            Test.startTest();
            List<MatchProviders.Response> res = invoke(need.Id, null);
            Test.stopTest();

            System.assertEquals(1, res[0].matches.size(), 'Expected one match');
            System.assert(res[0].matches[0].score > 0, 'Score should be > 0');
            System.assertNotEquals(null, res[0].matches[0].reason, 'Reason should be populated');
            System.assertEquals(null, res[0].noMatchReason, 'No noMatchReason when matches exist');
        }
    }

    // Row 2: service type excluded -> dropped
    @isTest
    static void dropsProviderMissingServiceType() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed('Eldercare', 'Bengaluru',
                new List<String>{'Tue'}, new List<String>{'Afternoon'});
            TestDataFactory.createProvider('ChildOnly', 'Childcare', 'Bengaluru', true, 3, 0, 5.0,
                new List<String>{'Tue'}, new List<String>{'Afternoon'});

            Test.startTest();
            List<MatchProviders.Response> res = invoke(need.Id, null);
            Test.stopTest();

            System.assertEquals(0, res[0].matches.size(), 'Provider without service type must be dropped');
            System.assertNotEquals(null, res[0].noMatchReason, 'noMatchReason should be set');
        }
    }

    // Row 3: unverified otherwise perfect -> dropped
    @isTest
    static void dropsUnverifiedProvider() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed('Eldercare', 'Bengaluru',
                new List<String>{'Tue'}, new List<String>{'Afternoon'});
            TestDataFactory.createProvider('Unverified', 'Eldercare', 'Bengaluru', false, 3, 0, 5.0,
                new List<String>{'Tue'}, new List<String>{'Afternoon'});

            Test.startTest();
            List<MatchProviders.Response> res = invoke(need.Id, null);
            Test.stopTest();

            System.assertEquals(0, res[0].matches.size(), 'Unverified provider must never surface');
        }
    }

    // Row 4: beyond radius (geo) and different city -> dropped
    @isTest
    static void dropsProviderOutOfRangeAndDifferentCity() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed('Eldercare', 'Bengaluru',
                new List<String>{'Tue'}, new List<String>{'Afternoon'}, BLR_LAT, BLR_LNG);
            // ~300km away (Chennai), small radius, different city
            TestDataFactory.createProviderWithGeo('Far', 'Eldercare', 'Chennai', true, 3, 0, 5.0,
                new List<String>{'Tue'}, new List<String>{'Afternoon'}, 13.0827, 80.2707, 10);

            Test.startTest();
            List<MatchProviders.Response> res = invoke(need.Id, null);
            Test.stopTest();

            System.assertEquals(0, res[0].matches.size(), 'Provider beyond radius in a different city must be dropped');
        }
    }

    // Row 5: identical except rating -> higher rating ranks first
    @isTest
    static void higherRatingRanksFirst() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed('Respite', 'Bengaluru',
                new List<String>{'Mon'}, new List<String>{'Morning'});
            TestDataFactory.createProvider('Low', 'Respite', 'Bengaluru', true, 5, 0, 3.0,
                new List<String>{'Mon'}, new List<String>{'Morning'});
            Provider_Profile__c high = TestDataFactory.createProvider('High', 'Respite', 'Bengaluru', true, 5, 0, 4.9,
                new List<String>{'Mon'}, new List<String>{'Morning'});

            Test.startTest();
            List<MatchProviders.Response> res = invoke(need.Id, null);
            Test.stopTest();

            System.assertEquals(2, res[0].matches.size(), 'Both should match');
            System.assertEquals(high.Id, res[0].matches[0].providerId, 'Higher-rated provider ranks first');
        }
    }

    // Row 6: active >= capacity -> dropped
    @isTest
    static void dropsProviderAtCapacity() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed('Meals', 'Bengaluru',
                new List<String>{'Fri'}, new List<String>{'Evening'});
            TestDataFactory.createProvider('Full', 'Meals', 'Bengaluru', true, 2, 2, 5.0,
                new List<String>{'Fri'}, new List<String>{'Evening'});

            Test.startTest();
            List<MatchProviders.Response> res = invoke(need.Id, null);
            Test.stopTest();

            System.assertEquals(0, res[0].matches.size(), 'Provider at/over capacity must be dropped');
        }
    }

    // Row 7: fuller availability overlap scores higher
    @isTest
    static void fullerOverlapScoresHigher() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed('Childcare', 'Bengaluru',
                new List<String>{'Mon','Tue'}, new List<String>{'Morning','Afternoon'});
            Provider_Profile__c partial = TestDataFactory.createProvider('Partial', 'Childcare', 'Bengaluru', true, 5, 0, 4.0,
                new List<String>{'Mon'}, new List<String>{'Morning'});
            Provider_Profile__c full = TestDataFactory.createProvider('Full', 'Childcare', 'Bengaluru', true, 5, 0, 4.0,
                new List<String>{'Mon','Tue'}, new List<String>{'Morning','Afternoon'});

            Test.startTest();
            List<MatchProviders.Response> res = invoke(need.Id, null);
            Test.stopTest();

            Map<Id, Integer> scoreById = new Map<Id, Integer>();
            for (MatchProviders.MatchResult m : res[0].matches) {
                scoreById.put(m.providerId, m.score);
            }
            System.assert(scoreById.get(full.Id) > scoreById.get(partial.Id),
                'Fuller availability overlap should score higher');
        }
    }

    // Row 8: no provider passes -> empty list + noMatchReason, no exception
    @isTest
    static void noMatchReturnsReason() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed('Transport', 'Bengaluru',
                new List<String>{'Sun'}, new List<String>{'Overnight'});
            TestDataFactory.createProvider('Wrong', 'Meals', 'Mysuru', true, 5, 0, 5.0,
                new List<String>{'Mon'}, new List<String>{'Morning'});

            Test.startTest();
            List<MatchProviders.Response> res = invoke(need.Id, null);
            Test.stopTest();

            System.assertEquals(0, res[0].matches.size(), 'No matches expected');
            System.assertNotEquals(null, res[0].noMatchReason, 'noMatchReason must be provided');
        }
    }

    // Row 9: bulk - list of requests processed in one call
    @isTest
    static void bulkRequestsProcessed() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need1 = TestDataFactory.createNeed('Eldercare', 'Bengaluru',
                new List<String>{'Tue'}, new List<String>{'Afternoon'});
            Care_Need__c need2 = TestDataFactory.createNeed('Meals', 'Bengaluru',
                new List<String>{'Fri'}, new List<String>{'Evening'});
            TestDataFactory.createProvider('Elder', 'Eldercare', 'Bengaluru', true, 3, 0, 4.5,
                new List<String>{'Tue'}, new List<String>{'Afternoon'});
            TestDataFactory.createProvider('Meal', 'Meals', 'Bengaluru', true, 3, 0, 4.2,
                new List<String>{'Fri'}, new List<String>{'Evening'});

            List<MatchProviders.Request> reqs = new List<MatchProviders.Request>();
            MatchProviders.Request r1 = new MatchProviders.Request();
            r1.careNeedId = need1.Id;
            MatchProviders.Request r2 = new MatchProviders.Request();
            r2.careNeedId = need2.Id;
            reqs.add(r1);
            reqs.add(r2);

            Test.startTest();
            List<MatchProviders.Response> res = MatchProviders.matchProviders(reqs);
            Test.stopTest();

            System.assertEquals(2, res.size(), 'One response per request');
            System.assertEquals(1, res[0].matches.size(), 'First need matched');
            System.assertEquals(1, res[1].matches.size(), 'Second need matched');
            System.assert(Limits.getQueries() < 100, 'SOQL must not be in a loop');
        }
    }

    // maxResults cap -> top N only
    @isTest
    static void capsToMaxResults() {
        User u = TestDataFactory.createTestUser();
        System.runAs(u) {
            Care_Need__c need = TestDataFactory.createNeed('Respite', 'Bengaluru',
                new List<String>{'Mon'}, new List<String>{'Morning'});
            for (Integer i = 0; i < 5; i++) {
                TestDataFactory.createProvider('P' + i, 'Respite', 'Bengaluru', true, 5, 0, 3.0 + (i * 0.1),
                    new List<String>{'Mon'}, new List<String>{'Morning'});
            }

            Test.startTest();
            List<MatchProviders.Response> res = invoke(need.Id, 3);
            Test.stopTest();

            System.assertEquals(3, res[0].matches.size(), 'Should cap to top 3');
        }
    }

    private static List<MatchProviders.Response> invoke(Id careNeedId, Integer maxResults) {
        MatchProviders.Request req = new MatchProviders.Request();
        req.careNeedId = careNeedId;
        req.maxResults = maxResults;
        return MatchProviders.matchProviders(new List<MatchProviders.Request>{ req });
    }
}
