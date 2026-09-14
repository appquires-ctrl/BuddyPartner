/**
 * Centralized Indian GST and pricing utility for all digital assets in BuddyPartner
 * (Coin packs, Membership subscriptions, VIP features, Gifts, etc.).
 *
 * Rate: 18% GST (Goods and Services Tax).
 */
const GST_RATE = 0.18;

/**
 * Calculates base price, 18% GST, and total tax-inclusive customer price.
 * @param {number} basePriceRupees 
 * @returns {{ basePriceRupees: number, gstRupees: number, totalPriceRupees: number }}
 */
function calculateAssetPricing(basePriceRupees) {
  const gstRupees = Math.round(basePriceRupees * GST_RATE);
  const totalPriceRupees = basePriceRupees + gstRupees;
  return {
    basePriceRupees,
    gstRupees,
    totalPriceRupees,
  };
}

module.exports = {
  GST_RATE,
  calculateAssetPricing,
};
