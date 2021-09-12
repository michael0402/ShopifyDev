# ================================ Customizable Settings ================================
# ================================================================
# Show Gateway(s) for Spend Threshold
#
# If the cart total is greater than, or equal to, the entered
# threshold, the entered gateway(s) are shown.
#
#   - 'threshold' is the dollar amount the customer must spend in
#     order to see the entered gateway(s)
#   - 'gateway_match_type' determines whether the below strings
#     should be an exact or partial match. Can be:
#       - ':exact' for an exact match
#       - ':partial' for a partial match
#   - 'gateway_names' is a list of strings to identify gateways
# ================================================================
SHOW_GATEWAYS_FOR_THRESHOLD = [
  {
    threshold: 500,
    gateway_match_type: :exact,
    gateway_names: ["Gateway", "Other Gateway"],
  },
]

# ================================ Script Code (do not edit) ================================
# ================================================================
# GatewayNameSelector
#
# Finds whether the supplied gateway name matches any of the
# entered names.
# ================================================================
class GatewayNameSelector
  def initialize(match_type, gateway_names)
    @comparator = match_type == :exact ? '==' : 'include?'
    @gateway_names = gateway_names.map { |name| name.downcase.strip }
  end

  def match?(payment_gateway)
    @gateway_names.any? { |name| payment_gateway.name.downcase.strip.send(@comparator, name) }
  end
end

# ================================================================
# ShowGatewaysForThresholdCampaign
#
# If the cart total is greater than, or equal to, the entered
# threshold, the entered gateway(s) are shown.
# ================================================================
class ShowGatewaysForThresholdCampaign
  def initialize(campaigns)
    @campaigns = campaigns
  end

  def run(cart, payment_gateways)
    @campaigns.each do |campaign|
      next unless cart.subtotal_price < (Money.new(cents: 100) * campaign[:threshold])

      gateway_name_selector = GatewayNameSelector.new(
        campaign[:gateway_match_type],
        campaign[:gateway_names],
      )

      payment_gateways.delete_if do |payment_gateway|
        gateway_name_selector.match?(payment_gateway)
      end
    end
  end
end

CAMPAIGNS = [
  ShowGatewaysForThresholdCampaign.new(SHOW_GATEWAYS_FOR_THRESHOLD),
]

CAMPAIGNS.each do |campaign|
  campaign.run(Input.cart, Input.payment_gateways)
end

Output.payment_gateways = Input.payment_gateways