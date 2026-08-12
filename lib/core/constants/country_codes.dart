class CountryCode {
  final String name;
  final String code;
  final String flag;
  final String iso;
  final int minLength;
  final int maxLength;

  const CountryCode({
    required this.name,
    required this.code,
    required this.flag,
    required this.iso,
    this.minLength = 7,
    this.maxLength = 15,
  });

  String get searchKey => '${name.toLowerCase()} ${code.toLowerCase()} ${iso.toLowerCase()}';
}

class CountryCodes {
  static const CountryCode defaultCountry = CountryCode(
    name: 'India',
    code: '+91',
    flag: '🇮🇳',
    iso: 'IN',
    minLength: 10,
    maxLength: 10,
  );

  static const List<CountryCode> allCountries = [
    CountryCode(name: 'India', code: '+91', flag: '🇮🇳', iso: 'IN', minLength: 10, maxLength: 10),
    CountryCode(name: 'United States', code: '+1', flag: '🇺🇸', iso: 'US', minLength: 10, maxLength: 10),
    CountryCode(name: 'United Kingdom', code: '+44', flag: '🇬🇧', iso: 'GB', minLength: 10, maxLength: 10),
    CountryCode(name: 'Canada', code: '+1', flag: '🇨🇦', iso: 'CA', minLength: 10, maxLength: 10),
    CountryCode(name: 'Australia', code: '+61', flag: '🇦🇺', iso: 'AU', minLength: 9, maxLength: 10),
    CountryCode(name: 'United Arab Emirates', code: '+971', flag: '🇦🇪', iso: 'AE', minLength: 9, maxLength: 9),
    CountryCode(name: 'Saudi Arabia', code: '+966', flag: '🇸🇦', iso: 'SA', minLength: 9, maxLength: 9),
    CountryCode(name: 'Singapore', code: '+65', flag: '🇸🇬', iso: 'SG', minLength: 8, maxLength: 8),
    CountryCode(name: 'Germany', code: '+49', flag: '🇩🇪', iso: 'DE', minLength: 10, maxLength: 11),
    CountryCode(name: 'France', code: '+33', flag: '🇫🇷', iso: 'FR', minLength: 9, maxLength: 9),
    CountryCode(name: 'Japan', code: '+81', flag: '🇯🇵', iso: 'JP', minLength: 10, maxLength: 10),
    CountryCode(name: 'South Korea', code: '+82', flag: '🇰🇷', iso: 'KR', minLength: 9, maxLength: 10),
    CountryCode(name: 'Italy', code: '+39', flag: '🇮🇹', iso: 'IT', minLength: 9, maxLength: 10),
    CountryCode(name: 'Spain', code: '+34', flag: '🇪🇸', iso: 'ES', minLength: 9, maxLength: 9),
    CountryCode(name: 'Brazil', code: '+55', flag: '🇧🇷', iso: 'BR', minLength: 10, maxLength: 11),
    CountryCode(name: 'Mexico', code: '+52', flag: '🇲🇽', iso: 'MX', minLength: 10, maxLength: 10),
    CountryCode(name: 'Indonesia', code: '+62', flag: '🇮🇩', iso: 'ID', minLength: 9, maxLength: 12),
    CountryCode(name: 'Malaysia', code: '+60', flag: '🇲🇾', iso: 'MY', minLength: 9, maxLength: 10),
    CountryCode(name: 'Philippines', code: '+63', flag: '🇵🇭', iso: 'PH', minLength: 10, maxLength: 10),
    CountryCode(name: 'Thailand', code: '+66', flag: '🇹🇭', iso: 'TH', minLength: 9, maxLength: 9),
    CountryCode(name: 'Vietnam', code: '+84', flag: '🇻🇳', iso: 'VN', minLength: 9, maxLength: 10),
    CountryCode(name: 'Nepal', code: '+977', flag: '🇳🇵', iso: 'NP', minLength: 10, maxLength: 10),
    CountryCode(name: 'Bangladesh', code: '+880', flag: '🇧🇩', iso: 'BD', minLength: 10, maxLength: 10),
    //CountryCode(name: 'Pakistan', code: '+92', flag: '🇵🇰', iso: 'PK', minLength: 10, maxLength: 10),
    CountryCode(name: 'Sri Lanka', code: '+94', flag: '🇱🇰', iso: 'LK', minLength: 9, maxLength: 9),
    CountryCode(name: 'Qatar', code: '+974', flag: '🇶🇦', iso: 'QA', minLength: 8, maxLength: 8),
    CountryCode(name: 'Kuwait', code: '+965', flag: '🇰🇼', iso: 'KW', minLength: 8, maxLength: 8),
    CountryCode(name: 'Oman', code: '+968', flag: '🇴🇲', iso: 'OM', minLength: 8, maxLength: 8),
    CountryCode(name: 'Bahrain', code: '+973', flag: '🇧🇭', iso: 'BH', minLength: 8, maxLength: 8),
    CountryCode(name: 'South Africa', code: '+27', flag: '🇿🇦', iso: 'ZA', minLength: 9, maxLength: 9),
    CountryCode(name: 'Nigeria', code: '+234', flag: '🇳🇬', iso: 'NG', minLength: 10, maxLength: 10),
    CountryCode(name: 'Kenya', code: '+254', flag: '🇰🇪', iso: 'KE', minLength: 9, maxLength: 9),
    CountryCode(name: 'Egypt', code: '+20', flag: '🇪🇬', iso: 'EG', minLength: 10, maxLength: 10),
    CountryCode(name: 'Russia', code: '+7', flag: '🇷🇺', iso: 'RU', minLength: 10, maxLength: 10),
    CountryCode(name: 'Turkey', code: '+90', flag: '🇹🇷', iso: 'TR', minLength: 10, maxLength: 10),
    CountryCode(name: 'Netherlands', code: '+31', flag: '🇳🇱', iso: 'NL', minLength: 9, maxLength: 9),
    CountryCode(name: 'Switzerland', code: '+41', flag: '🇨🇭', iso: 'CH', minLength: 9, maxLength: 9),
    CountryCode(name: 'Sweden', code: '+46', flag: '🇸🇪', iso: 'SE', minLength: 9, maxLength: 9),
    CountryCode(name: 'Norway', code: '+47', flag: '🇳🇴', iso: 'NO', minLength: 8, maxLength: 8),
    CountryCode(name: 'Denmark', code: '+45', flag: '🇩🇰', iso: 'DK', minLength: 8, maxLength: 8),
    CountryCode(name: 'Ireland', code: '+353', flag: '🇮🇪', iso: 'IE', minLength: 9, maxLength: 9),
    CountryCode(name: 'New Zealand', code: '+64', flag: '🇳🇿', iso: 'NZ', minLength: 8, maxLength: 10),
    CountryCode(name: 'Argentina', code: '+54', flag: '🇦🇷', iso: 'AR', minLength: 10, maxLength: 11),
    CountryCode(name: 'Colombia', code: '+57', flag: '🇨🇴', iso: 'CO', minLength: 10, maxLength: 10),
    CountryCode(name: 'Chile', code: '+56', flag: '🇨🇱', iso: 'CL', minLength: 9, maxLength: 9),
    CountryCode(name: 'Peru', code: '+51', flag: '🇵🇪', iso: 'PE', minLength: 9, maxLength: 9),
  ];

  static CountryCode findByCode(String code) {
    final clean = code.startsWith('+') ? code : '+$code';
    return allCountries.firstWhere(
      (c) => c.code == clean,
      orElse: () => defaultCountry,
    );
  }
}
