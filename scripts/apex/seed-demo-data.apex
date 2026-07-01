/**
 * CareCircle demo seed — non-PII, fictional South India (Bengaluru) personas.
 * Idempotent: deletes prior demo records (marked by DEMO_TAG) before re-inserting.
 * Run: sf apex run --file scripts/apex/seed-demo-data.apex --target-org "Hackathon Org"
 *
 * NO REAL PII. All names, contacts, and details are invented for the demo.
 */
final String DEMO_TAG = '[DEMO]';

// ---- Cleanup (order matters: Match restricts delete on Need/Provider) ----
// Note: Notes__c / Strain_Signals__c are Long Text Areas and can't be filtered with LIKE,
// so we key cleanup off the demo Contacts (filterable LastName) and their relationships.
String pat = '%' + DEMO_TAG + '%';
Set<Id> demoContactIds = new Map<Id, Contact>([SELECT Id FROM Contact WHERE LastName LIKE :pat]).keySet();
delete [SELECT Id FROM Match__c WHERE Care_Need__r.Seeker__c IN :demoContactIds];
delete [SELECT Id FROM Wellbeing_CheckIn__c WHERE Contact__c IN :demoContactIds];
delete [SELECT Id FROM Care_Need__c WHERE Seeker__c IN :demoContactIds];
delete [SELECT Id FROM Provider_Profile__c WHERE Name LIKE :pat];
delete [SELECT Id FROM Resource__c WHERE Name LIKE :pat];
delete [SELECT Id FROM Contact WHERE Id IN :demoContactIds];

// ---- Bengaluru locality geo (approximate) ----
Double JAYANAGAR_LAT = 12.9250, JAYANAGAR_LNG = 77.5938;
Double KORAMANGALA_LAT = 12.9352, KORAMANGALA_LNG = 77.6245;
Double WHITEFIELD_LAT = 12.9698, WHITEFIELD_LNG = 77.7500;

// ---- Contacts (seeker + providers) ----
Contact lakshmi = new Contact(FirstName='Lakshmi', LastName='(Seeker) ' + DEMO_TAG);
Contact selvi   = new Contact(FirstName='Selvi',   LastName='(Provider) ' + DEMO_TAG);
Contact anand   = new Contact(FirstName='Anand',   LastName='(Provider) ' + DEMO_TAG);
Contact priya   = new Contact(FirstName='Priya',   LastName='(Provider) ' + DEMO_TAG);
Contact ravi    = new Contact(FirstName='Ravi',    LastName='(Provider) ' + DEMO_TAG);
insert new List<Contact>{ lakshmi, selvi, anand, priya, ravi };

// ---- Providers ----
List<Provider_Profile__c> providers = new List<Provider_Profile__c>();

// Selvi — the hero match: verified, eldercare+respite, Jayanagar (same as Lakshmi),
// available Tue afternoons, high rating, capacity free. Should rank #1.
Provider_Profile__c pSelvi = new Provider_Profile__c(
    Name = 'Selvi R. ' + DEMO_TAG, Contact__c = selvi.Id,
    Services_Offered__c = 'Eldercare;Respite', City__c = 'Jayanagar',
    Availability_Day__c = 'Mon;Tue;Wed;Thu', Availability_Time_Block__c = 'Morning;Afternoon',
    Verified__c = true, Capacity__c = 3, Active_Match_Count__c = 0, Rating__c = 4.9,
    Service_Radius_Km__c = 8, Geolocation__Latitude__s = JAYANAGAR_LAT, Geolocation__Longitude__s = JAYANAGAR_LNG);
providers.add(pSelvi);

// Anand — decent alt: verified eldercare, nearby Koramangala, partial availability, good rating.
Provider_Profile__c pAnand = new Provider_Profile__c(
    Name = 'Anand K. ' + DEMO_TAG, Contact__c = anand.Id,
    Services_Offered__c = 'Eldercare;Transport', City__c = 'Koramangala',
    Availability_Day__c = 'Tue;Fri', Availability_Time_Block__c = 'Afternoon;Evening',
    Verified__c = true, Capacity__c = 2, Active_Match_Count__c = 1, Rating__c = 4.3,
    Service_Radius_Km__c = 10, Geolocation__Latitude__s = KORAMANGALA_LAT, Geolocation__Longitude__s = KORAMANGALA_LNG);
providers.add(pAnand);

// Priya — verified eldercare but far (Whitefield) with small radius -> location-gated out.
Provider_Profile__c pPriya = new Provider_Profile__c(
    Name = 'Priya S. ' + DEMO_TAG, Contact__c = priya.Id,
    Services_Offered__c = 'Eldercare', City__c = 'Whitefield',
    Availability_Day__c = 'Tue', Availability_Time_Block__c = 'Afternoon',
    Verified__c = true, Capacity__c = 5, Active_Match_Count__c = 0, Rating__c = 5.0,
    Service_Radius_Km__c = 5, Geolocation__Latitude__s = WHITEFIELD_LAT, Geolocation__Longitude__s = WHITEFIELD_LNG);
providers.add(pPriya);

// Ravi — UNVERIFIED, otherwise perfect. Demonstrates the trust/safety gate live (never surfaces).
Provider_Profile__c pRavi = new Provider_Profile__c(
    Name = 'Ravi M. ' + DEMO_TAG, Contact__c = ravi.Id,
    Services_Offered__c = 'Eldercare;Respite', City__c = 'Jayanagar',
    Availability_Day__c = 'Tue', Availability_Time_Block__c = 'Afternoon',
    Verified__c = false, Capacity__c = 3, Active_Match_Count__c = 0, Rating__c = 4.8,
    Service_Radius_Km__c = 8, Geolocation__Latitude__s = JAYANAGAR_LAT, Geolocation__Longitude__s = JAYANAGAR_LNG);
providers.add(pRavi);

insert providers;

// ---- Lakshmi's care need (the demo request) ----
Care_Need__c need = new Care_Need__c(
    Seeker__c = lakshmi.Id, Care_Type__c = 'Eldercare', City__c = 'Jayanagar',
    Schedule__c = 'Tuesday afternoons, recurring', Recurrence__c = 'Weekly',
    Requested_Day__c = 'Tue', Requested_Time_Block__c = 'Afternoon',
    Urgency__c = 'High', Status__c = 'New',
    Geolocation__Latitude__s = JAYANAGAR_LAT, Geolocation__Longitude__s = JAYANAGAR_LNG,
    Notes__c = DEMO_TAG + ' Caring for father Raghavan (early-stage dementia); needs cover during Tue afternoon work calls.');
insert need;

// ---- Grounding resources (support group, benefit/scheme, local service, crisis line) ----
List<Resource__c> resources = new List<Resource__c>();
resources.add(new Resource__c(
    Name = 'Dementia Caregivers Support Circle — Bengaluru ' + DEMO_TAG,
    Resource_Type__c = 'Support Group', City__c = 'Bengaluru',
    Summary__c = 'Weekly peer support group for family caregivers of people living with dementia. Meets Thursday evenings; also has a Tamil-speaking sub-group.',
    Source_URL__c = 'https://example.org/dementia-support-blr', Is_Crisis_Resource__c = false));
resources.add(new Resource__c(
    Name = 'Senior Citizen Welfare & Elder Care Scheme ' + DEMO_TAG,
    Resource_Type__c = 'Benefit/Scheme', City__c = null,
    Summary__c = 'Government support for elderly care including day-care assistance and caregiver respite allowances for eligible families. Plain-language eligibility guidance.',
    Source_URL__c = 'https://example.gov/elder-care-scheme', Is_Crisis_Resource__c = false));
resources.add(new Resource__c(
    Name = 'Home Respite & Attender Service — Jayanagar ' + DEMO_TAG,
    Resource_Type__c = 'Local Service', City__c = 'Jayanagar',
    Summary__c = 'Verified in-home respite attenders for short daytime cover, booked by the hour. Useful for recurring weekday work commitments.',
    Source_URL__c = 'https://example.org/respite-jayanagar', Is_Crisis_Resource__c = false));
resources.add(new Resource__c(
    Name = 'Caregiver Mental Health Helpline (24x7) ' + DEMO_TAG,
    Resource_Type__c = 'Crisis Line', City__c = null,
    Summary__c = 'Free, confidential 24x7 helpline staffed by trained counsellors for caregivers in distress. If you or someone is in immediate danger, contact local emergency services. (Demo placeholder number — replace with a real, verified helpline before submission.)',
    Source_URL__c = 'https://example.org/caregiver-helpline', Is_Crisis_Resource__c = true));
insert resources;

System.debug('Seeded: 5 contacts, ' + providers.size() + ' providers, 1 care need, ' + resources.size() + ' resources.');
System.debug('Demo Care Need Id = ' + need.Id);
