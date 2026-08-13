class Advertisement {
  final String id;
  final String imageUrl;
  final String clickUrl;
  final int displayOrder;

  Advertisement({
    required this.id,
    required this.imageUrl,
    required this.clickUrl,
    required this.displayOrder,
  });

  factory Advertisement.fromJson(Map<String, dynamic> json) {
    return Advertisement(
      id: json['id']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      clickUrl: json['clickUrl']?.toString() ?? '',
      displayOrder: (json['displayOrder'] is int)
          ? json['displayOrder']
          : int.tryParse(json['displayOrder']?.toString() ?? '0') ?? 0,
    );
  }
}
