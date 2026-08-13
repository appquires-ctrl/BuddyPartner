class Advertisement {
  final String id;
  final String imageUrl;
  final String clickUrl;
  final bool isActive;
  final int displayOrder;
  final int clickCount;
  final String? createdAt;
  final String? updatedAt;

  Advertisement({
    required this.id,
    required this.imageUrl,
    required this.clickUrl,
    required this.isActive,
    required this.displayOrder,
    required this.clickCount,
    this.createdAt,
    this.updatedAt,
  });

  factory Advertisement.fromJson(Map<String, dynamic> json) {
    return Advertisement(
      id: json['id']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      clickUrl: json['clickUrl']?.toString() ?? '',
      isActive: json['isActive'] == true,
      displayOrder: (json['displayOrder'] is int)
          ? json['displayOrder']
          : int.tryParse(json['displayOrder']?.toString() ?? '0') ?? 0,
      clickCount: (json['clickCount'] is int)
          ? json['clickCount']
          : int.tryParse(json['clickCount']?.toString() ?? '0') ?? 0,
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
    );
  }
}
