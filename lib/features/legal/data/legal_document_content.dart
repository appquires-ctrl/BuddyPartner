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

/// LegalDocumentContent contains complete draft legal texts for LoopCall.
class LegalDocumentContent {
  LegalDocumentContent._();

  static const String defaultLastUpdated = 'July 25, 2026';
  static const String companyName = 'Appquires Tech';
  static const String companyEmail = 'support@appquires.com';
  static const String companyWebsite = 'www.appquires.com';
  static const String companyAddress =
      'GF-001, Mauryansh Elanza, Shyamal Cross Rd, Satelite, Jodhpur Char Rasta, Satelite Police Station, Ahmadabad City, Ahmedabad- 380015, Gujarat, India';
  static const String jurisdictionCity = 'Ahmedabad, Gujarat, India';

  // 1. Terms of Service
  static const LegalDocument termsOfService = LegalDocument(
    id: 'terms-of-service',
    title: 'Terms of Service',
    subtitle: 'Rules, user agreement & platform conditions',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'Official Terms of Service agreement governing access to LoopCall subscription plans and platform features.',
    sections: [
      LegalDocumentSection(
        title: '1. Important Notice & Legal Disclaimer',
        content:
            'Welcome to LoopCall (the "App"), operated by Appquires Tech ("Company", "we", "us", or "our"), having its registered address at GF-001, Mauryansh Elanza, Shyamal Cross Rd, Satelite, Jodhpur Char Rasta, Satelite Police Station, Ahmadabad City, Ahmedabad- 380015, Gujarat, India. These Terms of Service ("Terms") govern your access to and use of LoopCall, including our live voice/video calling features and subscription plans.\n\nBy creating an account or accessing LoopCall, you enter into a legally binding contract with Appquires Tech. If you do not agree to these Terms, you must immediately cease accessing or using the App.',
      ),
      LegalDocumentSection(
        title: '2. Eligibility & Age Requirement (18+ Only)',
        content:
            'LoopCall is strictly intended for individuals who are at least eighteen (18) years of age. By registering an account, you self-attest and warrant that you are 18 years of age or older.\n\nWe maintain zero tolerance for underage access. If we discover or have reason to suspect that an account belongs to anyone under 18, we reserve the right to immediately terminate the account without prior notice or refund of any subscription pass.',
      ),
      LegalDocumentSection(
        title: '3. Account Responsibilities & Security',
        content:
            '• Security: You are solely responsible for maintaining the confidentiality of your mobile number and one-time password (OTP) credentials.\n• Account Activity: You accept responsibility for all activities, calls, and subscription transactions that occur under your account.\n• Identity Attestation: You agree to provide accurate, current, and complete profile information (Name, Gender, Language, Date of Birth). Creating fake accounts, misleading profiles, or impersonating another person is strictly forbidden.',
      ),
      LegalDocumentSection(
        title: '4. Prohibited Conduct & Safety Obligations',
        content:
            'When participating in live audio/video matches, messaging, or interacting on LoopCall, you explicitly agree NOT to:\n\n'
            'a) Engage in harassment, bullying, intimidation, hate speech, stalking, or abusive behavior toward any user or host.\n'
            'b) Broadcast or transmit nudity, sexually explicit content, vulgar language, violence, or illegal acts during live calls.\n'
            'c) Share, solicit, or exchange off-platform contact details (such as whatsapp numbers, personal social media handles, messaging IDs, or financial account details) to circumvent the App or route around platform subscription rules.\n'
            'd) Impersonate any entity, celebrity, company representative, or other user.\n'
            'e) Engage in fraud, scamming, commercial solicitation, spamming, or unauthorized advertising.\n'
            'f) Attempt to reverse-engineer, exploit, hack, or disrupt LoopCall servers, real-time call connections, or payment processing APIs.',
      ),
      LegalDocumentSection(
        title: '5. Subscription Economy & Pass Access',
        content:
            '• Subscription Passes: Access to matchmaking, direct calling, and instant messaging for all users (both male and female) is provided exclusively via subscription passes (e.g. 1 Day Pass, 1 Week Pass, 1 Month Pass, 1 Year VIP). Subscriptions grant full unlimited access during the active pass period.\n'
            '• Non-Transferable: Subscriptions are strictly bound to your registered account and cannot be transferred, sold, or shared with third parties.',
      ),
      LegalDocumentSection(
        title: '6. Content Moderation & Account Enforcement',
        content:
            'We actively monitor, review reports, and enforce community standards. We reserve the absolute right to:\n\n'
            '• Suspend, restrict, or permanently ban any account found violating these Terms or Community Guidelines.\n'
            '• Terminate accounts involved in abusive behavior, off-platform solicitation, or fraudulent activity.\n'
            '• Forfeit active subscriptions linked to banned accounts.',
      ),
      LegalDocumentSection(
        title: '7. Matched Users Disclaimer (Unverified Strangers)',
        content:
            'YOU ACKNOWLEDGE AND AGREE THAT MATCHED USERS ARE UNVERIFIED STRANGERS. THE PLATFORM DOES NOT GUARANTEE ANY USER\'S IDENTITY, AGE, BACKGROUND, OR CONDUCT.\n\n'
            'LoopCall provides the real-time transportation infrastructure for audio and video calls, but does not control user interactions. You participate in live calls at your own risk and discretion. Exercise caution when interacting with strangers.',
      ),
      LegalDocumentSection(
        title: '8. Limitation of Liability',
        content:
            'To the maximum extent permitted by applicable law, Appquires Tech, its officers, directors, employees, and agents shall not be liable for any indirect, incidental, special, consequential, or punitive damages, including loss of profits, data, or goodwill, arising from your use of or inability to use the App.',
      ),
      LegalDocumentSection(
        title: '9. Dispute Resolution & Governing Law',
        content:
            'These Terms shall be governed by and construed in accordance with the laws of India. Any legal action, dispute, or proceeding arising out of or relating to these Terms shall be subject to the exclusive jurisdiction of the courts located in Ahmedabad, Gujarat, India.',
      ),
      LegalDocumentSection(
        title: '10. Changes to Terms',
        content:
            'We reserve the right to revise these Terms at any time. When changes are published, we will update the "Last Updated" date at the top of this page. Your continued use of LoopCall after revised Terms are posted constitutes acceptance of the updated Terms.',
      ),
      LegalDocumentSection(
        title: '11. Contact Information',
        content:
            'For any questions or legal inquiries regarding these Terms, please contact us at:\n\n'
            '• Email: support@appquires.com\n'
            '• Website: www.appquires.com\n'
            '• Address: GF-001, Mauryansh Elanza, Shyamal Cross Rd, Satelite, Jodhpur Char Rasta, Satelite Police Station, Ahmadabad City, Ahmedabad- 380015, Gujarat, India\n'
            '• Entity: Appquires Tech',
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
        'This privacy policy complies with Indian Information Technology (IT Rules 2021) guidelines and governs subscription and user data protection.',
    sections: [
      LegalDocumentSection(
        title: '1. Information We Collect',
        content:
            'We collect information to provide, maintain, and improve our live calling platform:\n\n'
            '• Account & Profile Information: Mobile whatsapp number, Full Name, Date of Birth, Gender, Preferred Language, and optional avatar image.\n'
            '• Call Metadata & Technical Data: Real-time call logs, call duration, timestamp, socket connection status, network performance, IP address, device model, and OS version.\n'
            '• Call Content Disclaimer: We do NOT record or store live audio/video call stream content unless explicitly notified for safety moderation. Calls are transmitted real-time via secure WebRTC protocols.\n'
            '• Transaction & Financial Logs: Subscription order IDs, payment transaction amounts, active subscription pass records, and billing logs. We do not store raw credit card numbers or UPI PINs.',
      ),
      LegalDocumentSection(
        title: '2. Authentication & Credential Management',
        content:
            'We utilize secure backend APIs and Authkey WhatsApp OTP service to verify user mobile numbers via WhatsApp OTP. User credentials and authorization tokens are transmitted over HTTPS encrypted channels and protected using industry-standard security practices.',
      ),
      LegalDocumentSection(
        title: '3. How We Use Your Data',
        content:
            'Your data is used strictly for legitimate operational purposes:\n\n'
            '• Matchmaking & Call Facilitation: Connecting compatible male and female users based on online availability and language preferences.\n'
            '• Safety, Moderation & Trust: Investigating user reports, detecting spam, preventing abuse, and enforcing Community Guidelines.\n'
            '• Billing & Ledger Management: Processing subscription purchases and keeping accurate billing records.\n'
            '• Customer Support: Responding to support inquiries and troubleshooting app connection issues.',
      ),
      LegalDocumentSection(
        title: '4. Third-Party Service Providers',
        content:
            'We share data with trusted third-party providers solely to transport calls and process payments:\n\n'
            '• Agora.io / WebRTC Infrastructure: Powers low-latency real-time voice and video transmission.\n'
            '• Razorpay / Payment Gateways: Securely processes subscription purchases and payment transactions.\n'
            '• Authkey.io: Provides WhatsApp OTP verification and messaging infrastructure.',
      ),
      LegalDocumentSection(
        title: '5. Data Retention & User Rights',
        content:
            '• Data Retention: We retain user profile data and transaction logs as long as your account remains active or as required by law (e.g. tax and financial record obligations under Indian law).\n'
            '• Access & Deletion Rights: You have the right to request access to your stored personal data or request permanent deletion of your account and associated profile data.\n'
            '• Request Submission: Submit data access or deletion requests by emailing support@appquires.com.',
      ),
      LegalDocumentSection(
        title: '6. Cookies, Storage & Analytics',
        content:
            'We use secure local application storage (e.g. Flutter SharedPreferences / Secure Storage) to maintain user login sessions and preference states. We may use anonymized analytics tools to evaluate app performance and crash telemetry.',
      ),
      LegalDocumentSection(
        title: '7. Privacy Inquiries & Contact Info',
        content:
            'If you have questions regarding this Privacy Policy or wish to exercise your privacy rights, please reach out to our privacy officer:\n\n'
            '• Privacy Officer Email: support@appquires.com\n'
            '• Legal Entity: Appquires Tech\n'
            '• Website: www.appquires.com\n'
            '• Address: GF-001, Mauryansh Elanza, Shyamal Cross Rd, Satelite, Jodhpur Char Rasta, Satelite Police Station, Ahmadabad City, Ahmedabad- 380015, Gujarat, India',
      ),
    ],
  );

  // 3. Community Guidelines
  static const LegalDocument communityGuidelines = LegalDocument(
    id: 'community-guidelines',
    title: 'Community Guidelines',
    subtitle: 'Standards for safe & respectful interactions',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'Written in clear, accessible language for all LoopCall users. Everyone on LoopCall must follow these standards.',
    sections: [
      LegalDocumentSection(
        title: '1. Respect & Be Kind',
        content:
            'LoopCall is built for genuine, friendly connections. Treat every user with respect.\n\n'
            '• Zero Bullying & Hate Speech: Harassment, hate speech, body shaming, religious disrespect, or racial slurs will result in immediate account suspension.\n'
            '• Respect Boundaries: If someone expresses discomfort or asks to end a call, respect their decision gracefully.',
      ),
      LegalDocumentSection(
        title: '2. Keep It Safe (18+ & Sexual Content Policy)',
        content:
            '• Adults Only (18+): You must be 18 years or older. Minor involvement is strictly banned.\n'
            '• No Nudity or Explicit Sexual Content: Broadcasters and callers are prohibited from showing nudity, performing sexual acts, or soliciting sexual favors on camera.\n'
            '• No Unwanted Sexual Solicitation: Sending unwelcome sexual messages or making graphic sexual demands is prohibited.',
      ),
      LegalDocumentSection(
        title: '3. No Off-Platform Routing or Scams',
        content:
            '• Keep Calls Inside LoopCall: Asking users to exchange personal whatsapp numbers, WhatsApp, Telegram, or social media handles to bypass platform subscription rules is strictly prohibited.\n'
            '• Anti-Fraud Policy: Asking for money transfers, sharing fake UPI payment links, or attempting financial scams will lead to immediate permanent ban and reporting to authorities.',
      ),
      LegalDocumentSection(
        title: '4. Be Authentic (No Impersonation)',
        content:
            'Use your real details and genuine profile photos. Do not use images of celebrities, public figures, or third parties without permission. Fake accounts and deceptive profiles are removed immediately.',
      ),
      LegalDocumentSection(
        title: '5. Reporting & Moderation Consequences',
        content:
            '• How Reporting Works: You can report any user during or after a call using the in-app report button.\n'
            '• Consequences: Our moderation team reviews reported accounts. Violations result in:\n'
            '  1. Warning or call feature restriction.\n'
            '  2. Temporary account suspension.\n'
            '  3. Permanent account termination & forfeiture of active subscription access.',
      ),
    ],
  );

  // 4. Refund Policy
  static const LegalDocument refundPolicy = LegalDocument(
    id: 'refund-policy',
    title: 'Refund Policy',
    subtitle: 'Subscription pass billing & refund rules',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'Clear terms governing subscription pass purchases and billing inquiries on LoopCall.',
    sections: [
      LegalDocumentSection(
        title: '1. Subscription Pass Purchases (Non-Refundable)',
        content:
            'All subscription pass purchases (1 Day Pass, 1 Week Pass, 1 Month Pass, 1 Year VIP) made through LoopCall are final, non-refundable, and non-exchangeable for cash, except as explicitly required by applicable law or app store policy (Google Play / Apple App Store).\n\n'
            'Subscriptions are activated immediately upon successful payment verification.',
      ),
      LegalDocumentSection(
        title: '2. Exceptions & App Store Refunds',
        content:
            'If you purchased a subscription via Google Play Billing or Apple In-App Purchase:\n\n'
            '• Store Policy: Refund requests are subject to the policies of Google Play or the Apple App Store.\n'
            '• Request Process: You may request a refund directly through your Google Play Account history or Apple ID purchase receipt.\n'
            '• Consumed Access: If a refund is granted by the store provider for a subscription pass, LoopCall reserves the right to cancel the subscription or suspend the account if fraudulent activity is detected.',
      ),
      LegalDocumentSection(
        title: '3. Technical Billing Errors',
        content:
            'In the event of a technical glitch where money was debited from your bank account or card but subscription status was not activated on your LoopCall account:\n\n'
            '• Contact Support: Email support@appquires.com with your transaction payment ID, registered mobile number, and order receipt.\n'
            '• Resolution: Upon verification with payment gateway logs (e.g. Razorpay), your subscription will be manually activated within 24–48 hours.',
      ),
      LegalDocumentSection(
        title: '4. Account Termination Impact',
        content:
            'If your account is terminated or suspended due to violations of our Terms of Service or Community Guidelines, any remaining active subscription period is forfeited and will not be refunded.',
      ),
    ],
  );

  // 5. Withdrawal / Subscription Terms
  static const LegalDocument withdrawalTerms = LegalDocument(
    id: 'withdrawal-terms',
    title: 'Subscription Terms',
    subtitle: 'Subscription access & service policies',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'Terms governing subscription pass access, features, and platform services for all users.',
    sections: [
      LegalDocumentSection(
        title: '1. Universal Subscription Model',
        content:
            'LoopCall operates on a unified subscription model for both male and female users. Access to matchmaking, direct voice/video calling, and instant messaging requires an active subscription pass.\n\n'
            'Subscription options include 1 Day Pass, 1 Week Pass, 1 Month Pass, and 1 Year VIP.',
      ),
      LegalDocumentSection(
        title: '2. Unlimited Pass Features',
        content:
            '• Full Access: Subscribers enjoy unlimited matchmaking attempts, voice/video calls, and direct messaging during their active subscription duration.\n'
            '• Auto-Expiration: Subscriptions automatically expire at the end of the selected duration unless renewed.',
      ),
      LegalDocumentSection(
        title: '3. Platform Guidelines & Safety',
        content:
            '• Genuine Usage: Subscriptions are for personal use only. Commercial exploitation, automated calling, or bot usage is strictly prohibited.\n'
            '• Compliance: All subscribers must comply with our Terms of Service and Community Guidelines during calls and chats.',
      ),
      LegalDocumentSection(
        title: '4. Termination & Forfeiture',
        content:
            'Active subscription access will be cancelled and forfeited if an account is suspended or banned for severe ToS or Community Guideline violations.',
      ),
      LegalDocumentSection(
        title: '5. Inquiries & Support',
        content:
            'For questions concerning subscription passes or billing status, contact support at support@appquires.com.',
      ),
    ],
  );

  static List<LegalDocument> get allDocuments => [
        termsOfService,
        privacyPolicy,
        communityGuidelines,
        refundPolicy,
        withdrawalTerms,
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
      case 'withdrawal-terms':
      case 'withdrawal':
        return withdrawalTerms;
      default:
        return termsOfService;
    }
  }
}
