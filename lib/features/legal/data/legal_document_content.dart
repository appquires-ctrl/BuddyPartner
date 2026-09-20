/// LegalDocumentSection represents a single titled block of legal text.
class LegalDocumentSection {
  final String title;
  final String content;

  const LegalDocumentSection({
    required this.title,
    required this.content,
  });
}

/// LegalDocument holds static content, last updated date, and sections for legal pages.
class LegalDocument {
  final String id;
  final String title;
  final String subtitle;
  final String lastUpdated;
  final String summaryNotice;
  final List<LegalDocumentSection> sections;

  const LegalDocument({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.lastUpdated,
    required this.summaryNotice,
    required this.sections,
  });
}

/// HelpFaqItem represents a question and answer item for the Help Center.
class HelpFaqItem {
  final String question;
  final String answer;
  final String category;

  const HelpFaqItem({
    required this.question,
    required this.answer,
    required this.category,
  });
}

/// LegalDocumentContent contains complete, compliant legal texts and FAQ items for BuddyPartner.
class LegalDocumentContent {
  LegalDocumentContent._();

  static const String defaultLastUpdated = 'August 31, 2026';
  static const String companyName = 'Appquires Global LLP';
  static const String companyEmail = 'support@buddypartner.in';
  static const String companyWebsite = 'www.appquires.com';
  static const String companyAddress =
      'Ahmadabad City, Ahmedabad- 380015, Gujarat, India';
  static const String jurisdictionCity = 'Ahmedabad, Gujarat, India';
  static const String grievanceOfficerName = 'Nodal Grievance Redressal Officer';

  // 1. Terms of Service
  static const LegalDocument termsOfService = LegalDocument(
    id: 'terms-of-service',
    title: 'Terms of Service',
    subtitle: 'Rules, user agreement & platform conditions',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'Official Terms of Service agreement governing access to BuddyPartner subscription passes, live calling, and platform features.',
    sections: [
      LegalDocumentSection(
        title: '1. Important Notice & Legal Disclaimer',
        content:
            'Welcome to BuddyPartner (the "App"), operated by Appquires Global LLP ("Company", "we", "us", or "our"), having its registered office at Ahmadabad City, Ahmedabad- 380015, Gujarat, India.\n\nThese Terms of Service ("Terms") govern your access to and use of the BuddyPartner mobile application, websites, software, live voice/video calling network, and subscription passes.\n\nBy creating an account, accessing, or using BuddyPartner, you agree to be bound by these Terms and our Privacy Policy. If you do not agree to these Terms, you must immediately uninstall and discontinue using the App.',
      ),
      LegalDocumentSection(
        title: '2. Eligibility & Strict Age Requirement (18+ Only)',
        content:
            'BuddyPartner is strictly designed for adults who are at least eighteen (18) years of age. By creating an account or accessing the App, you warrant and represent that:\n\n'
            '• You are at least 18 years old.\n'
            '• You have the legal capacity and authority to enter into these Terms under the laws of your jurisdiction.\n'
            '• You have never been convicted of a felony, sexual offense, or any crime involving violence.\n\n'
            'We enforce zero tolerance for underage usage. If we discover or have reason to suspect that any user is under 18, their account will be immediately terminated with permanent forfeiture of any active subscription passes.',
      ),
      LegalDocumentSection(
        title: '3. Account Security & Verification',
        content:
            '• Mobile & OTP Authentication: You must register with a valid mobile number verified via WhatsApp OTP. You are responsible for safeguarding your device and login credentials.\n'
            '• Account Responsibility: You are solely responsible for all activities, messages, and calls initiated under your account.\n'
            '• Profile Accuracy: You agree to provide genuine and accurate profile information (Name, Date of Birth, Gender, Language, Avatar). Misrepresenting your age, gender, or identity is strictly prohibited.',
      ),
      LegalDocumentSection(
        title: '4. Prohibited Conduct & Community Safety',
        content:
            'You agree to use BuddyPartner in a safe, courteous, and lawful manner. You strictly agree NOT to:\n\n'
            'a) Broadcast, transmit, or solicit nudity, sexual acts, pornographic material, or vulgar gestures during live audio/video calls.\n'
            'b) Engage in harassment, stalking, bullying, intimidation, threats, hate speech, religious or racial discrimination, or blackmail.\n'
            'c) Share or solicit off-platform contact details (such as personal phone numbers, WhatsApp, Telegram, Instagram, UPI handles, or bank accounts) to circumvent platform safety rules or subscription policies.\n'
            'd) Solicit money, advance fees, investments, gifts, or financial transfers from any user.\n'
            'e) Impersonate any person, brand, public figure, or company representative.\n'
            'f) Upload malicious code, use bots, automated match scrapers, or attempt to compromise server infrastructure or Agora real-time audio/video streams.\n'
            'g) Engage in any activity that exploits or endangers minors (Child Sexual Abuse Material - CSAM). Any such activity results in immediate permanent ban and direct reporting to law enforcement authorities.',
      ),
      LegalDocumentSection(
        title: '5. Universal Subscription Model & Pass Economy',
        content:
            '• Universal Access: Access to matchmaking, direct voice/video calling, and messaging for all users (both male and female) is provided exclusively via Subscription Passes (e.g., 1 Day Pass, 1 Week Pass, 1 Month Pass, 1 Year VIP).\n'
            '• Unlimited Usage During Validity: An active subscription pass grants unlimited calling and messaging privileges during the validity window.\n'
            '• Auto-Expiration: Passes expire automatically upon the conclusion of the chosen time period and must be renewed for continued calling access.\n'
            '• Non-Transferable: Subscriptions are strictly non-transferable, non-assignable, and cannot be resold or transferred to any other account.',
      ),
      LegalDocumentSection(
        title: '6. Live Calling Disclaimer (Unverified Strangers)',
        content:
            'YOU EXPRESSLY ACKNOWLEDGE THAT BUDDYPARTNER CONNECTS YOU WITH OTHER REGISTERED USERS WHO ARE INDEPENDENT THIRD PARTIES AND UNVERIFIED STRANGERS.\n\n'
            'BuddyPartner provides the real-time communications infrastructure (via WebRTC / Agora) to facilitate voice and video connections. BuddyPartner does not conduct criminal background checks or verify the private statements of every user. You interact with other users entirely at your own risk and judgment.',
      ),
      LegalDocumentSection(
        title: '7. Content Moderation, Reporting & Account Enforcement',
        content:
            'We actively maintain real-time reporting mechanisms and automated safety monitors. We reserve the absolute discretion to:\n\n'
            '• Investigate any user report submitted via the in-app reporting tool.\n'
            '• Restrict calling features, issue warnings, or impose temporary suspensions.\n'
            '• Permanently terminate accounts violating these Terms or Community Guidelines.\n'
            '• Forfeit any active subscription pass balance without refund upon account termination for cause.',
      ),
      LegalDocumentSection(
        title: '8. Intellectual Property Rights',
        content:
            'All intellectual property rights in the BuddyPartner application, including design, brand trademarks, logos, UI code, graphics, audio algorithms, and databases, are the sole property of Appquires Global LLP. You are granted a limited, personal, non-exclusive, non-transferable, revocable license to use the App solely for personal, non-commercial entertainment.',
      ),
      LegalDocumentSection(
        title: '9. Limitation of Liability',
        content:
            'To the maximum extent permitted by applicable law, Appquires Global LLP, its partners, officers, employees, and agents shall not be liable for any direct, indirect, incidental, special, consequential, or punitive damages, including loss of data, profits, emotional distress, or damages arising out of user conduct or inability to use the platform.\n\nIn no event shall our total aggregate liability exceed the total amount paid by you for subscription passes in the three (3) months preceding the claim.',
      ),
      LegalDocumentSection(
        title: '10. Governing Law, Dispute Resolution & Jurisdiction',
        content:
            'These Terms and any dispute or claim arising out of or related to BuddyPartner shall be governed by and construed in accordance with the substantive laws of India.\n\nAll disputes, claims, or controversies shall be subject to the exclusive jurisdiction of the competent courts located in Ahmedabad, Gujarat, India.',
      ),
      LegalDocumentSection(
        title: '11. Grievance Redressal & Contact Information',
        content:
            'In accordance with the Information Technology Act, 2000 and the Information Technology (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021, you may contact our designated Grievance Officer:\n\n'
            '• Designation: Nodal Grievance Redressal Officer\n'
            '• Support & Grievance Email: support@buddypartner.in\n'
            '• Company: Appquires Global LLP\n'
            '• Address: Ahmadabad City, Ahmedabad- 380015, Gujarat, India\n'
            '• Response Timeline: Acknowledgment within 24 hours; disposal/resolution within 15 days.',
      ),
    ],
  );

  // 2. Privacy Policy
  static const LegalDocument privacyPolicy = LegalDocument(
    id: 'privacy-policy',
    title: 'Privacy Policy',
    subtitle: 'How your data is collected, used & protected',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'This Privacy Policy complies with the Information Technology Act 2000, IT (Intermediary Guidelines) Rules 2021, and the Digital Personal Data Protection (DPDP) Act, 2023.',
    sections: [
      LegalDocumentSection(
        title: '1. Information We Collect',
        content:
            'We collect limited information essential to provide secure authentication, matchmaking, and subscription management:\n\n'
            '• Profile Information: Mobile number (for WhatsApp OTP login), Full Name, Date of Birth, Gender, Preferred Language, and selected avatar.\n'
            '• Technical & Device Data: Device model, operating system version, unique device identifier, IP address, connection speed, socket telemetry, and app crash logs.\n'
            '• Call Metadata: Timestamps of initiated calls, call connection status, duration, call rating, and reporting logs.\n'
            '• Transaction Data: Subscription order IDs, purchase timestamps, pass type, and payment gateway confirmation receipts (e.g. Google Play). We NEVER collect or store credit/debit card numbers, CVV, or UPI PINs.',
      ),
      LegalDocumentSection(
        title: '2. Live Audio & Video Call Privacy (No Stream Recording)',
        content:
            '• Unrecorded Streams: Your live audio and video calls are transmitted peer-to-peer or via ultra-low-latency real-time servers using encrypted WebRTC protocols (powered by Agora.io).\n'
            '• Zero Permanent Recording: We do NOT record, intercept, or store live video feeds or voice streams of your 1-on-1 calls on our servers under standard operational mode.\n'
            '• Screenshot & Privacy Protection: The app enforces platform-level screen recording and screenshot restrictions where supported to protect user privacy.',
      ),
      LegalDocumentSection(
        title: '3. Authentication & Verification',
        content:
            'We utilize secure API endpoints and verified WhatsApp OTP delivery providers (such as MSG91) to authenticate your registered mobile number. All authentication tokens and API communications are encrypted via TLS/HTTPS 256-bit encryption.',
      ),
      LegalDocumentSection(
        title: '4. How We Use Collected Information',
        content:
            'Your data is processed strictly for the following purposes:\n\n'
            '• Matchmaking & Connection: Finding compatible users according to mutual language and availability preferences.\n'
            '• Trust, Safety & Enforcement: Investigating reported harassment, preventing spam, detecting ban-evasion, and maintaining a respectful community.\n'
            '• Subscription Fulfillment: Verifying pass payments and updating account access privileges in real time.\n'
            '• Service Improvement & Support: Resolving technical issues, debugging latency/connection errors, and answering customer support inquiries.',
      ),
      LegalDocumentSection(
        title: '5. Third-Party Service Providers',
        content:
            'We share minimum necessary data with trusted infrastructure providers:\n\n'
            '• Agora.io: Real-time audio and video communications infrastructure.\n'
            '• App Stores: Secure payment gateways processing subscription pass purchases.\n'
            '• MSG91: WhatsApp OTP delivery service.\n'
            '• Firebase / Google Cloud: Secure cloud infrastructure and push notifications.\n\n'
            'We NEVER sell, rent, or trade your personal data to third-party advertisers or data brokers.',
      ),
      LegalDocumentSection(
        title: '6. Data Retention & User Rights (DPDP Act Compliance)',
        content:
            'Under the Digital Personal Data Protection Act (DPDP Act) and applicable regulations, you enjoy full control over your personal data:\n\n'
            '• Right to Access & Correction: You can view and update your profile details directly from the Account screen.\n'
            '• Right to Erasure / Account Deletion: You can permanently delete your account and all associated profile data at any time from Profile -> Delete Account, or by emailing support@buddypartner.in.\n'
            '• Deletion Process: Upon account deletion, personal profile identifiers are permanently purged from active databases within 7 days, subject to statutory tax and financial transaction retention laws required by Indian authorities.',
      ),
      LegalDocumentSection(
        title: '7. Cookies, Local Storage & Security Safeguards',
        content:
            '• Local Secure Storage: We use encrypted local device storage (Flutter Secure Storage) to maintain encrypted session tokens and user preference states.\n'
            '• Data Security: We implement administrative, physical, and technical safeguards including encrypted database storage, strict role-based access control, and firewalled backend clusters to protect your information.',
      ),
      LegalDocumentSection(
        title: '8. Privacy Enquiries & Grievance Redressal Officer',
        content:
            'For any questions, clarifications, or requests regarding your personal data or privacy rights, please reach out to:\n\n'
            '• Grievance Officer: Nodal Grievance Redressal Officer\n'
            '• Privacy Email: support@buddypartner.in\n'
            '• Entity: Appquires Global LLP\n'
            '• Address: Ahmadabad City, Ahmedabad- 380015, Gujarat, India',
      ),
    ],
  );

  // 3. Community Guidelines
  static const LegalDocument communityGuidelines = LegalDocument(
    id: 'community-guidelines',
    title: 'Community Guidelines',
    subtitle: 'Standards for safe, authentic & respectful interactions',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'Clear standards governing all interactions on BuddyPartner. Every user must follow these guidelines to keep the community safe.',
    sections: [
      LegalDocumentSection(
        title: '1. Respect & Courtesy for Everyone',
        content:
            'BuddyPartner is built to foster friendly, meaningful, and respectful 1-on-1 conversations.\n\n'
            '• Zero Tolerance for Hate Speech: Harassment, racial slurs, religious intolerance, caste-based comments, disability shaming, or body shaming will result in immediate permanent suspension.\n'
            '• Respect Boundaries: If another user does not wish to speak or asks to end a call, respect their decision immediately.',
      ),
      LegalDocumentSection(
        title: '2. Nudity, Sexual Content & 18+ Rules',
        content:
            '• Adults Only: You must be 18 years of age or older. Minors are strictly prohibited from using BuddyPartner.\n'
            '• No Nudity or Sexual Acts: Displaying nudity, showing genitals, performing explicit sexual acts, or soliciting sexual services during live audio/video calls is strictly banned.\n'
            '• Zero Tolerance for CSAM: Any transmission or solicitation of child sexual abuse material results in immediate account ban, hardware device ban, and reporting to law enforcement agencies and cybercrime authorities.',
      ),
      LegalDocumentSection(
        title: '3. Anti-Fraud & Off-Platform Solicitation Policy',
        content:
            '• Keep Conversations In-App: Do NOT ask other users for personal phone numbers, WhatsApp numbers, Telegram usernames, or Instagram IDs to circumvent subscription rules or lure users off-platform.\n'
            '• No Financial Demands: Asking for money transfers, UPI payments, recharge requests, gift cards, or investment schemes is strictly banned.\n'
            '• Anti-Blackmail & Anti-Extortion: Threatening users with screenshots, extortion, or recording calls will lead to immediate criminal prosecution and platform bans.',
      ),
      LegalDocumentSection(
        title: '4. Authenticity (No Impersonation or Fake Profiles)',
        content:
            '• Real Information: Use accurate profile information and your genuine avatar representation.\n'
            '• No Impersonation: Do not pretend to be someone else, use photos of celebrities, or falsely claim to represent BuddyPartner staff or customer support.',
      ),
      LegalDocumentSection(
        title: '5. In-App Reporting & Enforcement Actions',
        content:
            '• How to Report: Use the in-call or post-call report button to flag any inappropriate behavior immediately.\n'
            '• Investigation & Penalty Hierarchy:\n'
            '  1. Formal Warning and calling feature restriction.\n'
            '  2. Temporary Account Suspension (24h - 7 days).\n'
            '  3. Permanent Account & Device Ban with complete forfeiture of active subscription passes.',
      ),
    ],
  );

  // 4. Refund & Cancellation Policy
  static const LegalDocument refundPolicy = LegalDocument(
    id: 'refund-policy',
    title: 'Refund Policy',
    subtitle: 'Subscription pass billing, cancellation & refund terms',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'Clear terms governing subscription pass purchases, store refunds, and technical payment disputes on BuddyPartner.',
    sections: [
      LegalDocumentSection(
        title: '1. Subscription Passes (Non-Refundable Once Activated)',
        content:
            'All subscription pass purchases (1 Day Pass, 1 Week Pass, 1 Month Pass, 1 Year VIP) made on BuddyPartner grant immediate digital access to real-time voice and video calling features.\n\n'
            'Due to the immediate provisioning of real-time server bandwidth and matchmaking infrastructure, all subscription purchases are final, non-refundable, and non-exchangeable for cash once activated, except as required by law or official app store policies.',
      ),
      LegalDocumentSection(
        title: '2. Google Play & Apple App Store Purchases',
        content:
            'If you purchased your subscription pass via Google Play In-App Billing or Apple In-App Purchase:\n\n'
            '• Applicable Store Rules: Refund requests are governed by Google Play or Apple App Store policies.\n'
            '• How to Request: You can request a refund directly via Google Play Order History (play.google.com) or Apple Report a Problem (reportaproblem.apple.com).\n'
            '• Subscription Revocation: If Google or Apple grants a refund, the corresponding subscription pass will be automatically revoked from your BuddyPartner account.',
      ),
      LegalDocumentSection(
        title: '3. Technical Billing Errors & Glitch Resolution',
        content:
            'In rare cases where your bank account, card, or UPI was debited but the subscription pass was not activated in the app due to network latency:\n\n'
            '• Step 1: Please wait 15 minutes and restart the application.\n'
            '• Step 2: If the pass is still inactive, email support@buddypartner.in with your registered mobile number, payment transaction ID, and bank receipt.\n'
            '• Step 3: Our billing team will verify with the payment gateway and manually activate your pass or initiate a direct gateway refund within 24 to 48 hours.',
      ),
      LegalDocumentSection(
        title: '4. Violations & Account Termination Impact',
        content:
            'If an account is suspended or permanently banned due to a violation of our Terms of Service, Community Guidelines, or Safety Policies, any remaining time on active subscription passes is forfeited without entitlement to any refund.',
      ),
      LegalDocumentSection(
        title: '5. Chargebacks & Payment Inquiries',
        content:
            'If you notice an unrecognized charge or have questions regarding a subscription invoice, please contact us at support@buddypartner.in before filing an external dispute so we can resolve the issue swiftly.',
      ),
    ],
  );

  // 5. Subscription Terms
  static const LegalDocument subscriptionTerms = LegalDocument(
    id: 'subscription-terms',
    title: 'Subscription Terms',
    subtitle: 'Subscription passes, access rules & validity guidelines',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'Terms governing subscription pass privileges, feature access, and validity durations for all BuddyPartner users.',
    sections: [
      LegalDocumentSection(
        title: '1. Universal Subscription Pass Model',
        content:
            'BuddyPartner operates on an all-inclusive subscription pass model. Rather than paying per minute, users purchase flexible time-based passes that unlock full platform capabilities:\n\n'
            '• 1 Day Pass: 24-hour unlimited voice & video calling and instant messaging access.\n'
            '• 1 Week Pass: 7-day full unlimited access.\n'
            '• 1 Month Pass: 30-day comprehensive unlimited access.\n'
            '• 1 Year VIP Pass: 365-day premium uninterrupted access with priority matchmaking.',
      ),
      LegalDocumentSection(
        title: '2. Pass Features & Unlimited Calling Privileges',
        content:
            'During the active duration of any valid subscription pass, users receive:\n\n'
            '• Unlimited voice and video call matchmaking.\n'
            '• Direct audio/video calling with online profiles.\n'
            '• Instant messaging and chat conversations.\n'
            '• No per-minute deductions or hidden fees.',
      ),
      LegalDocumentSection(
        title: '3. Validity & Expiration Rules',
        content:
            '• Precise Countdown: Pass validity starts immediately upon payment confirmation and runs continuously in real-time until expiration.\n'
            '• No Pausing: Passes cannot be paused, suspended, or put on hold.\n'
            '• Renewal: Once a pass expires, calling and chat features pause until a new pass is purchased.',
      ),
      LegalDocumentSection(
        title: '4. Fair Usage & Commercial Use Prohibition',
        content:
            '• Personal Use Only: Subscription passes are intended exclusively for personal, individual social interactions.\n'
            '• Prohibited Activities: Automated autodialers, commercial marketing broadcasts, call-center operations, or bot integration are strictly prohibited and will result in immediate termination without refund.',
      ),
      LegalDocumentSection(
        title: '5. Pricing Changes & Billing Support',
        content:
            'We reserve the right to modify subscription pass prices or offer promotional discounts. Any price change will apply only to subsequent purchases and will not affect currently active passes. For billing support, email support@buddypartner.in.',
      ),
    ],
  );

  // 6. Safety & Anti-Fraud Guidelines
  static const LegalDocument safetyGuidelines = LegalDocument(
    id: 'safety-guidelines',
    title: 'Safety & Anti-Fraud Guidelines',
    subtitle: 'Essential online safety tips, fraud protection & scam prevention',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'Follow these critical safety guidelines to protect your identity, privacy, and finances while interacting with other users.',
    sections: [
      LegalDocumentSection(
        title: '1. Never Share Financial Details or Send Money',
        content:
            '• Zero Financial Transfers: NEVER send money, transfer funds via UPI, buy gift cards, or share bank account details with anyone you meet on the App, regardless of how compelling their story or emergency sounds.\n'
            '• Keep OTPs Secret: Never share your WhatsApp OTP, banking OTP, or passwords with anyone. BuddyPartner staff will NEVER ask for your OTP or password.',
      ),
      LegalDocumentSection(
        title: '2. Keep Conversations on BuddyPartner',
        content:
            '• Stay On-Platform: Scammers and fraudsters frequently ask you to move conversations to WhatsApp, Telegram, or social media handles to bypass in-app safety monitors.\n'
            '• Protect Your Personal Phone Number: Keep your personal phone number, home address, workplace, and private social media profiles confidential.',
      ),
      LegalDocumentSection(
        title: '3. Live Audio/Video Call Safety & Sextortion Prevention',
        content:
            '• Guard Your Privacy on Camera: Be mindful of your surroundings and personal privacy while on video calls. Do NOT engage in sexually compromising acts on camera.\n'
            '• Beware of Recording Blackmail: Scammers may attempt to record screen footage and demand money under threat of publishing videos. If anyone threatens you, DO NOT pay. Block and report them immediately and contact law enforcement.',
      ),
      LegalDocumentSection(
        title: '4. Recognizing Common Online Dating Scams',
        content:
            'Be vigilant against common scam tactics:\n\n'
            '• Emergency / Medical Crisis: Claiming sudden illness, travel crisis, or hospital emergency and asking for urgent funds.\n'
            '• Fake Investment Schemes: Promising high returns through crypto, foreign exchange, or third-party betting links.\n'
            '• Travel / Meetup Deposit Scams: Demanding advance travel or ticket money before meeting.\n'
            '• Impersonation: Posing as military personnel, celebrities, or corporate executives.',
      ),
      LegalDocumentSection(
        title: '5. In-App Reporting & Blocking',
        content:
            '• Instant Reporting: You can report abusive, suspicious, or inappropriate users at any time using the Report button during or after a call.\n'
            '• Immediate Blocking: Blocking a user immediately prevents them from calling, messaging, or appearing in your matchmaking queue.',
      ),
      LegalDocumentSection(
        title: '6. Law Enforcement & Emergency Helpline Contacts',
        content:
            'If you are in immediate danger or a victim of cybercrime, fraud, or extortion:\n\n'
            '• National Cyber Crime Reporting Portal (India): https://cybercrime.gov.in\n'
            '• National Cyber Financial Fraud Helpline: 1930\n'
            '• National Emergency Helpline (India): 112\n'
            '• BuddyPartner Safety Team: support@buddypartner.in',
      ),
    ],
  );

  // 7. Grievance Redressal Policy (IT Rules 2021 Statutory Compliance)
  static const LegalDocument grievancePolicy = LegalDocument(
    id: 'grievance-redressal',
    title: 'Grievance Redressal Policy',
    subtitle: 'Statutory compliance under Indian IT Rules 2021',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'Formal grievance redressal mechanism established pursuant to Rule 3(2) of the Information Technology (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021.',
    sections: [
      LegalDocumentSection(
        title: '1. Regulatory Mandate & Applicability',
        content:
            'In compliance with the Information Technology Act, 2000 and Rule 3(2) of the Information Technology (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021, Appquires Global LLP has established a dedicated Grievance Redressal Mechanism to address user complaints and concerns regarding platform access, content moderation, privacy violations, or user conduct.',
      ),
      LegalDocumentSection(
        title: '2. Designated Grievance Redressal Officer',
        content:
            'Users and authorities may address any grievance, violation, or legal notice to our designated officer:\n\n'
            '• Officer Title: Nodal Grievance Redressal Officer\n'
            '• Legal Entity: Appquires Global LLP\n'
            '• Support & Grievance Email: support@buddypartner.in\n'
            '• Registered Physical Address: Ahmadabad City, Ahmedabad- 380015, Gujarat, India\n'
            '• Business Hours: Monday to Friday, 10:00 AM to 6:00 PM IST (excluding public holidays)',
      ),
      LegalDocumentSection(
        title: '3. Grievance Submission Procedure',
        content:
            'To lodge a formal grievance, please submit an email to support@buddypartner.in containing:\n\n'
            '1. Your registered mobile number on BuddyPartner.\n'
            '2. Detailed description of the grievance, along with the reported user\'s profile name or timestamp of the call/interaction.\n'
            '3. Relevant screenshots or supporting evidence (if available).\n'
            '4. Specific remedy or corrective action requested.',
      ),
      LegalDocumentSection(
        title: '4. Statutory Timelines for Grievance Resolution',
        content:
            'In accordance with Indian IT Rules 2021:\n\n'
            '• Acknowledgment: Every formal grievance will be acknowledged with a unique reference ticket within twenty-four (24) hours of receipt.\n'
            '• Disposal & Resolution: The grievance will be thoroughly investigated and formally disposed of / resolved within fifteen (15) days from the date of receipt.\n'
            '• Expedited Removal: In cases involving non-consensual sexual content, nudity, or impersonation, content removal actions will be executed within twenty-four (24) hours of receiving valid notice.',
      ),
      LegalDocumentSection(
        title: '5. Grievance Appellate Committee (GAC)',
        content:
            'If you are dissatisfied with the resolution provided by our Grievance Officer, you may appeal the decision before the Grievance Appellate Committee (GAC) established by the Central Government of India under Rule 3A of the IT Rules 2021 via their portal: https://gac.gov.in.',
      ),
    ],
  );

  // Backward compatibility alias for legacy withdrawalTerms reference
  static LegalDocument get withdrawalTerms => subscriptionTerms;

  static List<LegalDocument> get allDocuments => [
        termsOfService,
        privacyPolicy,
        communityGuidelines,
        refundPolicy,
        subscriptionTerms,
        safetyGuidelines,
        grievancePolicy,
      ];

  static LegalDocument getById(String id) {
    switch (id) {
      case 'terms-of-service':
      case 'terms':
        return termsOfService;
      case 'privacy-policy':
      case 'privacy':
        return privacyPolicy;
      case 'community-guidelines':
      case 'community':
        return communityGuidelines;
      case 'refund-policy':
      case 'refund':
        return refundPolicy;
      case 'subscription-terms':
      case 'subscription':
      case 'withdrawal-terms':
      case 'withdrawal':
        return subscriptionTerms;
      case 'safety-guidelines':
      case 'safety':
        return safetyGuidelines;
      case 'grievance-redressal':
      case 'grievance':
        return grievancePolicy;
      default:
        return termsOfService;
    }
  }

  // FAQ Questions & Answers list for Help Center
  static const List<HelpFaqItem> helpFaqs = [
    HelpFaqItem(
      question: 'How do Subscription Passes work?',
      answer:
          'BuddyPartner uses flexible Subscription Passes (1 Day, 1 Week, 1 Month, and 1 Year VIP). An active pass gives you unlimited voice & video calls, matchmaking, and direct messaging without per-minute fees.',
      category: 'Subscriptions',
    ),
    HelpFaqItem(
      question: 'Are my voice and video calls recorded or stored?',
      answer:
          'No. All 1-on-1 audio and video calls are transmitted in real time over encrypted WebRTC protocols. We do not record, intercept, or store your live audio or video streams.',
      category: 'Privacy & Calls',
    ),
    HelpFaqItem(
      question: 'Is my phone number visible to other users?',
      answer:
          'No. Your registered mobile number is kept strictly confidential and is never shared with or visible to other users. Only your display name, age, language, and avatar are shown.',
      category: 'Privacy & Safety',
    ),
    HelpFaqItem(
      question: 'How do I report or block an abusive user?',
      answer:
          'You can tap the Report or Block icon directly on the active call screen or post-call summary. Our moderation team reviews flagged users, and blocking immediately prevents further calls.',
      category: 'Safety & Moderation',
    ),
    HelpFaqItem(
      question: 'Money was debited but my subscription pass is inactive. What should I do?',
      answer:
          'Please wait 10–15 minutes and restart the app. If your pass is still inactive, email support@buddypartner.in with your payment transaction ID and registered number. We will verify and activate your pass within 24–48 hours.',
      category: 'Billing & Payments',
    ),
    HelpFaqItem(
      question: 'How can I permanently delete my account and data?',
      answer:
          'Go to Profile -> Delete Account and confirm your decision. All personal profile details and active sessions will be permanently purged in accordance with our Privacy Policy.',
      category: 'Account',
    ),
  ];
}
