import 'package:flutter/material.dart';

/// Represents an icebreaker question with text, category, and theme color.
class IcebreakerQuestion {
  final String id;
  final String text;
  final String category;
  final IconData icon;
  final Color primaryColor;
  final Color secondaryColor;

  const IcebreakerQuestion({
    required this.id,
    required this.text,
    required this.category,
    required this.icon,
    required this.primaryColor,
    required this.secondaryColor,
  });
}

/// Curated list of engaging icebreaker questions for dating app calls.
const List<IcebreakerQuestion> kIcebreakerQuestions = [
  IcebreakerQuestion(
    id: '1',
    text: "What's your biggest turn-on in a relationship?",
    category: 'Flirty',
    icon: Icons.local_fire_department_rounded,
    primaryColor: Color(0xFFFF416C),
    secondaryColor: Color(0xFFFF4B2B),
  ),
  IcebreakerQuestion(
    id: '2',
    text: "What's your dream first date scenario?",
    category: 'Romance',
    icon: Icons.favorite_rounded,
    primaryColor: Color(0xFFE100FF),
    secondaryColor: Color(0xFF7F00FF),
  ),
  IcebreakerQuestion(
    id: '3',
    text: "What's a secret goal you haven't told anyone yet?",
    category: 'Deep',
    icon: Icons.psychology_rounded,
    primaryColor: Color(0xFF00B4DB),
    secondaryColor: Color(0xFF0083B0),
  ),
  IcebreakerQuestion(
    id: '4',
    text: "Would you rather travel 100 years into past or future?",
    category: 'Hypothetical',
    icon: Icons.alt_route_rounded,
    primaryColor: Color(0xFF11998E),
    secondaryColor: Color(0xFF38EF7D),
  ),
  IcebreakerQuestion(
    id: '5',
    text: "What's your most embarrassing date memory?",
    category: 'Funny',
    icon: Icons.sentiment_very_satisfied_rounded,
    primaryColor: Color(0xFFFF9900),
    secondaryColor: Color(0xFFFF5500),
  ),
  IcebreakerQuestion(
    id: '6',
    text: "What's the most romantic song on your playlist?",
    category: 'Vibes',
    icon: Icons.music_note_rounded,
    primaryColor: Color(0xFF8E2DE2),
    secondaryColor: Color(0xFF4A00E0),
  ),
  IcebreakerQuestion(
    id: '7',
    text: "What green flag do you look for first in someone?",
    category: 'Insight',
    icon: Icons.verified_user_rounded,
    primaryColor: Color(0xFF00F2FE),
    secondaryColor: Color(0xFF4FACFE),
  ),
  IcebreakerQuestion(
    id: '8',
    text: "If we went on a trip tomorrow, where are we heading?",
    category: 'Adventure',
    icon: Icons.flight_takeoff_rounded,
    primaryColor: Color(0xFFF857A6),
    secondaryColor: Color(0xFFFF5858),
  ),
];
