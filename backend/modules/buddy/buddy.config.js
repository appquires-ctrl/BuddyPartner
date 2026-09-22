/**
 * Configuration for "Buddy" Activity Requests feature.
 * Centralized pricing and limits so updates do not require database migrations.
 */

const BUDDY_TYPES = Object.freeze({
  movie: {
    id: 'movie',
    title: 'Movie Buddy',
    subtitle: 'Find someone to watch movies with',
    stickerPath: 'assets/images/stickers/movie_buddy.png',
  },
  pizza: {
    id: 'pizza',
    title: 'Pizza Buddy',
    subtitle: 'Find someone to grab delicious pizza with',
    stickerPath: 'assets/images/stickers/pizza_buddy.png',
  },
  coffee: {
    id: 'coffee',
    title: 'Coffee Buddy',
    subtitle: 'Find someone for a coffee chat',
    stickerPath: 'assets/images/stickers/coffee_buddy.png',
  },
  hangout: {
    id: 'hangout',
    title: 'Hangout Buddy',
    subtitle: 'Find someone to chill and hangout with',
    stickerPath: 'assets/images/stickers/hangout_buddy.png',
  },
  trip: {
    id: 'trip',
    title: 'Trip Buddy',
    subtitle: 'Find a travel partner for your next trip',
    stickerPath: 'assets/images/stickers/trip_buddy.png',
  },
  cricket: {
    id: 'cricket',
    title: 'Cricket Buddy',
    subtitle: 'Find a buddy to watch or play cricket',
    stickerPath: 'assets/images/stickers/cricket_buddy.png',
  },
  shopping: {
    id: 'shopping',
    title: 'Shopping Buddy',
    subtitle: 'Find someone to go shopping with',
    stickerPath: 'assets/images/stickers/shopping_buddy.png',
  },
  night_out: {
    id: 'night_out',
    title: 'Night Out Buddy',
    subtitle: 'Find a partner for a fun night out',
    stickerPath: 'assets/images/stickers/nightout_buddy.png',
  },
  clubbing: {
    id: 'clubbing',
    title: 'Clubbing Buddy',
    subtitle: 'Find a party and clubbing partner',
    stickerPath: 'assets/images/stickers/clubbing_buddy.png',
  },
  long_drive: {
    id: 'long_drive',
    title: 'Long Drive Buddy',
    subtitle: 'Find someone for a scenic long drive',
    stickerPath: 'assets/images/stickers/longdrive_buddy.png',
  },
  garba: {
    id: 'garba',
    title: 'Garba Buddy',
    subtitle: 'Find someone who matches your Garba vibes',
    stickerPath: 'assets/images/stickers/garba_buddy.png',
  },
  festival: {
    id: 'festival',
    title: 'Festival Buddy',
    subtitle: 'Celebrate festivals and special events together',
    stickerPath: 'assets/images/stickers/garba_buddy.png',
  },
});

const BUDDY_PRICING = Object.freeze({
  INITIATOR_COIN_COST: 100, // Fallback default
  GARBA_INITIATOR_COIN_COST: 509, // Garba Buddy Group Host cost: 509 coins for 6-person group
  ACCEPTER_COIN_REWARD: 50, // Fallback default
  FEMALE_REWARD_PERCENTAGE: 0.40, // 40% of broadcast coin cost for female accepters
  MALE_REWARD_PERCENTAGE: 0.20, // 20% of broadcast coin cost for male accepters
  TYPE_COIN_COSTS: Object.freeze({
    movie: 1999,
    pizza: 499,
    coffee: 499,
    hangout: 999,
    trip: 999,
    cricket: 199,
    shopping: 799,
    night_out: 2499,
    clubbing: 1499,
    long_drive: 999,
    garba: 509,
    festival: 1,
  }),
});

const BUDDY_LIMITS = Object.freeze({
  MAX_OTP_ATTEMPTS: 5,
  OTP_LOCKOUT_SECONDS: 900, // 15 minutes lockout
  MAX_FCM_BATCH_SIZE: 500,
  MAX_FCM_RECIPIENTS: 5000,
  DEFAULT_FEED_LIMIT: 20,
  MAX_FEED_LIMIT: 50,
});

const BUDDY_STATUSES = Object.freeze({
  OPEN: 'open',
  ACCEPTED: 'accepted',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
});

module.exports = {
  BUDDY_TYPES,
  BUDDY_PRICING,
  BUDDY_LIMITS,
  BUDDY_STATUSES,
};
