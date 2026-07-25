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

  // 1. Terms of Service
  static const LegalDocument termsOfService = LegalDocument(
    id: 'terms-of-service',
    title: 'Terms of Service',
    subtitle: 'Rules, user agreement & platform conditions',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'DRAFT DOCUMENT — NOT LEGAL ADVICE. This placeholder terms agreement is subject to final review by legal counsel prior to commercial launch.',
    sections: [
      LegalDocumentSection(
        title: '1. Important Notice & Legal Disclaimer',
        content:
            'Welcome to LoopCall (the "App"), operated by [Company Legal Name] ("Company", "we", "us", or "our"), having its registered address at [Registered Address]. These Terms of Service ("Terms") govern your access to and use of LoopCall, including our live voice/video calling features, coin purchases, and rose reward system.\n\nBy creating an account or accessing LoopCall, you enter into a legally binding contract with [Company Legal Name]. If you do not agree to these Terms, you must immediately cease accessing or using the App.',
      ),
      LegalDocumentSection(
        title: '2. Eligibility & Age Requirement (18+ Only)',
        content:
            'LoopCall is strictly intended for individuals who are at least eighteen (18) years of age. By registering an account, you self-attest and warrant that you are 18 years of age or older.\n\nWe maintain zero tolerance for underage access. If we discover or have reason to suspect that an account belongs to anyone under 18, we reserve the right to immediately terminate the account without prior notice or refund of any virtual currency.',
      ),
      LegalDocumentSection(
        title: '3. Account Responsibilities & Security',
        content:
            '• Security: You are solely responsible for maintaining the confidentiality of your mobile number and one-time password (OTP) credentials.\n• Account Activity: You accept responsibility for all activities, calls, and virtual currency transactions that occur under your account.\n• Identity Attestation: You agree to provide accurate, current, and complete profile information (Name, Gender, Language, Date of Birth). Creating fake accounts, misleading profiles, or impersonating another person is strictly forbidden.',
      ),
      LegalDocumentSection(
        title: '4. Prohibited Conduct & Safety Obligations',
        content:
            'When participating in live audio/video matches, messaging, or interacting on LoopCall, you explicitly agree NOT to:\n\n'
            'a) Engage in harassment, bullying, intimidation, hate speech, stalking, or abusive behavior toward any user or host.\n'
            'b) Broadcast or transmit nudity, sexually explicit content, vulgar language, violence, or illegal acts during live calls.\n'
            'c) Share, solicit, or exchange off-platform contact details (such as phone numbers, personal social media handles, messaging IDs, or financial account details) to circumvent the App or route around platform charges.\n'
            'd) Impersonate any entity, celebrity, company representative, or other user.\n'
            'e) Engage in fraud, scamming, commercial solicitation, spamming, or unauthorized advertising.\n'
            'f) Attempt to reverse-engineer, exploit, hack, or disrupt LoopCall servers, real-time call connections, or payment processing APIs.',
      ),
      LegalDocumentSection(
        title: '5. Virtual Currency Economy (Coins & Roses)',
        content:
            '• Coins (Purchased Currency): Coins are virtual items purchased with fiat money to initiate calls, extend duration, or send virtual gifts. Coins hold no cash value, do not earn interest, and are strictly non-refundable except where mandated by law or app store policy.\n'
            '• Roses (Earned Currency): Roses are virtual tokens received by hosts during live calls. Roses represent provisional reward units that may convert to fiat currency subject to manual review, identity verification, and future Withdrawal Terms.\n'
            '• Non-Transferable: Coins and Roses cannot be transferred, sold, or exchanged outside the official LoopCall application.',
      ),
      LegalDocumentSection(
        title: '6. Content Moderation & Account Enforcement',
        content:
            'We actively monitor, review reports, and enforce community standards. We reserve the absolute right to:\n\n'
            '• Suspend, restrict, or permanently ban any account found violating these Terms or Community Guidelines.\n'
            '• Terminate accounts involved in abusive behavior, off-platform solicitation, or fraudulent activity.\n'
            '• Forfeit accumulated virtual currencies (Coins or Roses) linked to banned accounts.',
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
            'To the maximum extent permitted by applicable law, [Company Legal Name], its officers, directors, employees, and agents shall not be liable for any indirect, incidental, special, consequential, or punitive damages, including loss of profits, data, or goodwill, arising from your use of or inability to use the App.',
      ),
      LegalDocumentSection(
        title: '9. Dispute Resolution & Governing Law',
        content:
            'These Terms shall be governed by and construed in accordance with the laws of India. Any legal action, dispute, or proceeding arising out of or relating to these Terms shall be subject to the exclusive jurisdiction of the courts located in [Jurisdiction / City, India].',
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
            '• Email: [Contact Email]\n'
            '• Address: [Registered Address]\n'
            '• Entity: [Company Legal Name]',
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
        'DRAFT DOCUMENT — NOT LEGAL ADVICE. This placeholder privacy policy complies with Indian Information Technology (IT Rules 2021) guidelines and is subject to final review prior to launch.',
    sections: [
      LegalDocumentSection(
        title: '1. Information We Collect',
        content:
            'We collect information to provide, maintain, and improve our live calling platform:\n\n'
            '• Account & Profile Information: Mobile phone number, Full Name, Date of Birth, Gender, Preferred Language, and optional avatar image.\n'
            '• Call Metadata & Technical Data: Real-time call logs, call duration, timestamp, socket connection status, network performance, IP address, device model, and OS version.\n'
            '• Call Content Disclaimer: We do NOT record or store live audio/video call stream content unless explicitly notified for safety moderation. Calls are transmitted real-time via secure WebRTC protocols.\n'
            '• Transaction & Financial Logs: Recharge order IDs, payment transaction amounts, coin balances, rose earnings, and withdrawal request records. We do not store raw credit card numbers or UPI PINs.',
      ),
      LegalDocumentSection(
        title: '2. Authentication & Credential Management',
        content:
            'We utilize Firebase Authentication and our secure backend APIs to verify user mobile numbers via SMS OTP. User credentials and authorization tokens are transmitted over HTTPS encrypted channels and protected using industry-standard security practices.',
      ),
      LegalDocumentSection(
        title: '3. How We Use Your Data',
        content:
            'Your data is used strictly for legitimate operational purposes:\n\n'
            '• Matchmaking & Call Facilitation: Connecting compatible male and female users based on online availability and language preferences.\n'
            '• Safety, Moderation & Trust: Investigating user reports, detecting spam, preventing abuse, and enforcing Community Guidelines.\n'
            '• Billing & Ledger Management: Processing coin recharges, tracking rose accumulation, and keeping accurate financial records.\n'
            '• Customer Support: Responding to support inquiries and troubleshooting app connection issues.',
      ),
      LegalDocumentSection(
        title: '4. Third-Party Service Providers',
        content:
            'We share data with trusted third-party providers solely to transport calls and process payments:\n\n'
            '• Agora.io / WebRTC Infrastructure: Powers low-latency real-time voice and video transmission.\n'
            '• Razorpay / Payment Gateways: Securely processes coin recharge purchases and payment transactions.\n'
            '• Firebase (Google): Provides SMS OTP verification, analytics, and cloud infrastructure.',
      ),
      LegalDocumentSection(
        title: '5. Data Retention & User Rights',
        content:
            '• Data Retention: We retain user profile data and transaction logs as long as your account remains active or as required by law (e.g. tax and financial record obligations under Indian law).\n'
            '• Access & Deletion Rights: You have the right to request access to your stored personal data or request permanent deletion of your account and associated profile data.\n'
            '• Request Submission: Submit data access or deletion requests by emailing [Privacy Contact Email].',
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
            '• Privacy Officer Email: [Privacy Contact Email]\n'
            '• Legal Entity: [Company Legal Name]\n'
            '• Address: [Registered Address]',
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
            '• Keep Calls Inside LoopCall: Asking users to exchange personal phone numbers, WhatsApp, Telegram, or social media handles to bypass platform coin rates is strictly prohibited.\n'
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
            '  3. Permanent account termination & forfeiture of virtual coin/rose balances.',
      ),
    ],
  );

  // 4. Refund Policy
  static const LegalDocument refundPolicy = LegalDocument(
    id: 'refund-policy',
    title: 'Refund Policy',
    subtitle: 'Coin recharge billing & refund rules',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'Clear terms governing coin pack purchases and billing inquiries on LoopCall.',
    sections: [
      LegalDocumentSection(
        title: '1. Coin Pack Purchases (Non-Refundable)',
        content:
            'All coin recharges and virtual currency purchases made through LoopCall are final, non-refundable, and non-exchangeable for cash, except as explicitly required by applicable law or app store policy (Google Play / Apple App Store).\n\n'
            'Coins are consumed immediately when initiating or participating in live calls and sending virtual gifts.',
      ),
      LegalDocumentSection(
        title: '2. Exceptions & App Store Refunds',
        content:
            'If you purchased coins via Google Play Billing or Apple In-App Purchase:\n\n'
            '• Store Policy: Refund requests are subject to the policies of Google Play or the Apple App Store.\n'
            '• Request Process: You may request a refund directly through your Google Play Account history or Apple ID purchase receipt.\n'
            '• Consumed Currency: If a refund is granted by the store provider for a coin pack that has already been spent, LoopCall reserves the right to deduct the equivalent coin amount or suspend the account if the balance becomes negative.',
      ),
      LegalDocumentSection(
        title: '3. Technical Billing Errors',
        content:
            'In the event of a technical glitch where money was debited from your bank account or card but coin balance was not credited to your LoopCall wallet:\n\n'
            '• Contact Support: Email [Contact Email] with your transaction payment ID, registered phone number, and order screenshot.\n'
            '• Resolution: Upon verification with payment gateway logs (e.g. Razorpay), your wallet balance will be manually updated within 24–48 hours.',
      ),
      LegalDocumentSection(
        title: '4. Account Termination Impact',
        content:
            'If your account is terminated or suspended due to violations of our Terms of Service or Community Guidelines, any remaining unspent coin balance is forfeited and will not be refunded.',
      ),
    ],
  );

  // 5. Withdrawal Terms
  static const LegalDocument withdrawalTerms = LegalDocument(
    id: 'withdrawal-terms',
    title: 'Withdrawal Terms',
    subtitle: 'Rose reward conversions & payout policies',
    lastUpdated: defaultLastUpdated,
    summaryNotice:
        'IMPORTANT NOTICE: Real-money automated payout processing is currently under development. Withdrawal requests are subject to manual review.',
    sections: [
      LegalDocumentSection(
        title: '1. Manual Review & Verification Notice',
        content:
            'Real-money withdrawal functionality for converting accumulated Rose rewards into fiat currency (Indian Rupees - INR) is subject to manual administrative review.\n\n'
            'Final payout processing timelines, automated payment gateway integration, minimum payout thresholds, and statutory tax deduction rules (TDS under Indian IT Act) will be formally published before automated payouts go live.',
      ),
      LegalDocumentSection(
        title: '2. Host Eligibility & Rose Accumulation',
        content:
            '• Earned Rewards: Roses are provisional reward points awarded by callers during legitimate, interactive live calls.\n'
            '• Genuine Activity: Roses earned through artificial calling schemes, self-calling, collusion, bots, or fraudulent activity are void.\n'
            '• Identity Verification (KYC): Hosts requesting withdrawal payouts will be required to complete identity verification (PAN / Aadhaar / Bank Account attestation) prior to funds disbursement.',
      ),
      LegalDocumentSection(
        title: '3. Processing Expectations & Manual Audit',
        content:
            '• Manual Audit: All submitted withdrawal requests undergo a manual safety audit to verify call authenticity and host compliance with Community Guidelines.\n'
            '• Timeline Disclaimer: Do not rely on fixed payout schedules during the current preview period. Payout processing schedules will be specified upon formal launch of the automated payout system.',
      ),
      LegalDocumentSection(
        title: '4. Forfeiture of Rewards',
        content:
            'Rose balances and pending withdrawal requests will be cancelled and forfeited if:\n\n'
            'a) The host account is suspended or banned for severe ToS or Community Guideline violations (e.g. nudity, minor involvement, off-platform payment routing).\n'
            'b) The host provides fraudulent identity or bank account details during payout request processing.',
      ),
      LegalDocumentSection(
        title: '5. Inquiries & Support',
        content:
            'For questions concerning Rose reward balances or host payout status, contact host support at [Contact Email].',
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
