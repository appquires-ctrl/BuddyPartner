/**
 * Configuration for "Buddy" Activity Requests feature.
 * Centralized pricing and limits so updates do not require database migrations.
 */

const BUDDY_TYPES = Object.freeze({
  movie: {
    id: 'movie',
    title: 'Movie Buddy',
    subtitle: 'Find someone to watch movies with',
    stickerPath: 'assets/images/stickers/movie_buddy.jpg',
  },
  pizza: {
    id: 'pizza',
    title: 'Pizza Buddy',
    subtitle: 'Find someone to grab delicious pizza with',
    stickerPath: 'assets/images/stickers/pizza_buddy.jpg',
  },
  coffee: {
    id: 'coffee',
    title: 'Coffee Buddy',
    subtitle: 'Find someone for a coffee chat',
    stickerPath: 'assets/images/stickers/coffee_buddy.jpg',
  },
  hangout: {
    id: 'hangout',
    title: 'Hangout Buddy',
    subtitle: 'Find someone to chill and hangout with',
    stickerPath: 'assets/images/stickers/hangout_buddy.jpg',
  },
  trip: {
    id: 'trip',
    title: 'Trip Buddy',
    subtitle: 'Find a travel partner for your next trip',
    stickerPath: 'assets/images/stickers/trip_buddy.jpg',
  },
  cricket: {
    id: 'cricket',
    title: 'Cricket Buddy',
    subtitle: 'Find a buddy to watch or play cricket',
    stickerPath: 'assets/images/stickers/cricket_buddy.jpg',
  },
  shopping: {
    id: 'shopping',
    title: 'Shopping Buddy',
    subtitle: 'Find someone to go shopping with',
    stickerPath: 'assets/images/stickers/shopping_buddy.jpg',
  },
  night_out: {
    id: 'night_out',
    title: 'Night Out Buddy',
    subtitle: 'Find a partner for a fun night out',
    stickerPath: 'assets/images/stickers/nightout_buddy.jpg',
  },
  clubbing: {
    id: 'clubbing',
    title: 'Clubbing Buddy',
    subtitle: 'Find a party and clubbing partner',
    stickerPath: 'assets/images/stickers/clubbing_buddy.jpg',
  },
  long_drive: {
    id: 'long_drive',
    title: 'Long Drive Buddy',
    subtitle: 'Find someone for a scenic long drive',
    stickerPath: 'assets/images/stickers/longdrive_buddy.jpg',
  },
});

const BUDDY_PRICING = Object.freeze({
  INITIATOR_COIN_COST: 100,
  ACCEPTER_COIN_REWARD: 50,
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
