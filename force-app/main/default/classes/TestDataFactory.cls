/**
 * TestDataFactory — central builder for CareCircle test data.
 *
 * Also provisions a least-privilege test user (Standard User profile + the
 * CareCircle permission set only). Tests run their logic inside
 * System.runAs(thatUser) so object CRUD and field-level security are genuinely
 * enforced — matching how a real community user (not an admin) hits the code.
 */
@isTest
public class TestDataFactory {
    /**
     * Creates a test user on a Standard User profile with ONLY the CareCircle
     * permission set assigned. Performs setup-object DML only (User +
     * PermissionSetAssignment), so call it before any non-setup DML in a test.
     */
    public static User createTestUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = 'cc' + Math.abs(Crypto.getRandomInteger());
        User u = new User(
            FirstName = 'Care',
            LastName = 'Tester',
            Email = 'carecircle.tester@example.com',
            Username = uniq + '@carecircle.test.example.com',
            Alias = 'cctest',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u;

        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'CareCircle' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        return u;
    }

    public static Contact createContact(String lastName) {
        Contact c = new Contact(LastName = lastName);
        insert c;
        return c;
    }

    public static Care_Need__c createNeed(String careType, String city, List<String> days, List<String> blocks) {
        return createNeed(careType, city, days, blocks, null, null);
    }

    public static Care_Need__c createNeed(
        String careType, String city, List<String> days, List<String> blocks, Double lat, Double lng
    ) {
        Contact seeker = createContact('Seeker');
        Care_Need__c n = new Care_Need__c(
            Seeker__c = seeker.Id,
            Care_Type__c = careType,
            City__c = city,
            Urgency__c = 'Medium',
            Status__c = 'New',
            Requested_Day__c = days == null ? null : String.join(days, ';'),
            Requested_Time_Block__c = blocks == null ? null : String.join(blocks, ';')
        );
        if (lat != null && lng != null) {
            n.Geolocation__Latitude__s = lat;
            n.Geolocation__Longitude__s = lng;
        }
        insert n;
        return n;
    }

    public static Provider_Profile__c createProvider(
        String name, String services, String city, Boolean verified,
        Decimal capacity, Decimal activeCount, Decimal rating,
        List<String> days, List<String> blocks
    ) {
        Provider_Profile__c p = buildProvider(name, services, city, verified, capacity, activeCount, rating, days, blocks);
        insert p;
        return p;
    }

    public static Provider_Profile__c createProviderWithGeo(
        String name, String services, String city, Boolean verified,
        Decimal capacity, Decimal activeCount, Decimal rating,
        List<String> days, List<String> blocks, Decimal lat, Decimal lng, Decimal radiusKm
    ) {
        Provider_Profile__c p = buildProvider(name, services, city, verified, capacity, activeCount, rating, days, blocks);
        p.Service_Radius_Km__c = radiusKm;
        p.Geolocation__Latitude__s = lat == null ? null : lat.doubleValue();
        p.Geolocation__Longitude__s = lng == null ? null : lng.doubleValue();
        insert p;
        return p;
    }

    private static Provider_Profile__c buildProvider(
        String name, String services, String city, Boolean verified,
        Decimal capacity, Decimal activeCount, Decimal rating,
        List<String> days, List<String> blocks
    ) {
        Contact c = createContact('Prov ' + name);
        return new Provider_Profile__c(
            Name = name,
            Contact__c = c.Id,
            Services_Offered__c = services,
            City__c = city,
            Verified__c = verified,
            Capacity__c = capacity,
            Active_Match_Count__c = activeCount,
            Rating__c = rating,
            Availability_Day__c = days == null ? null : String.join(days, ';'),
            Availability_Time_Block__c = blocks == null ? null : String.join(blocks, ';')
        );
    }
}
