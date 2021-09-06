# ================================ Customizable Settings ================================
# ================================================================
# Buy Products WXY, get Z Discount
#
# Buy a specific bundle of products, get that bundle at a
# discount. For example:
#
#   "Buy a t-shirt, a hat, and sunglasses, get 20% off each"
#
#   - 'bundle_items' is a list of the items that comprise the
#     bundle, where:
#     - 'product_id' is the ID of the product
#     - 'quantity_needed' is the quantity necessary to complete
#       the bundle
#   - 'discount_type' is the type of discount to provide. Can be
#     either:
#       - ':percent'
#       - ':dollar'
#   - 'discount_amount' is the percentage/dollar discount to
#     apply (per item)
#   - 'discount_message' is the message to show when a discount
#     is applied
# ================================================================
BUNDLE_DISCOUNTS = [
  {
    bundle_items: [
      {
        product_id: 1234567890987,
        quantity_needed: 1
      },
      {
        product_id: 1234567890986,
        quantity_needed: 1
      },
    ],
    discount_type: :percent,
    discount_amount: 10,
    discount_message: "Buy Product X and Product Y, get 10% off!",
  },
]

# ================================ Script Code (do not edit) ================================
# ================================================================
# BundleSelector
#
# Finds any items that are part of the entered bundle and saves
# them.
# ================================================================
class BundleSelector
  def initialize(bundle_items)
    @bundle_items = bundle_items.reduce({}) do |acc, bundle_item|
      acc[bundle_item[:product_id]] = {
        cart_items: [],
        quantity_needed: bundle_item[:quantity_needed],
        total_quantity: 0,
      }

      acc
    end
  end

  def build(cart)
    cart.line_items.each do |line_item|
            next if line_item.line_price_changed?
      next unless @bundle_items[line_item.variant.product.id]

      @bundle_items[line_item.variant.product.id][:cart_items].push(line_item)
      @bundle_items[line_item.variant.product.id][:total_quantity] += line_item.quantity
    end

    @bundle_items
  end
end

# ================================================================
# DiscountApplicator
#
# Applies the entered discount to the supplied line item.
# ================================================================
class DiscountApplicator
  def initialize(discount_type, discount_amount, discount_message)
    @discount_type = discount_type
    @discount_message = discount_message

    @discount_amount = if discount_type == :percent
      1 - (discount_amount * 0.01)
    else
      Money.new(cents: 100) * discount_amount
    end
  end

  def apply(line_item)
    new_line_price = if @discount_type == :percent
      line_item.line_price * @discount_amount
    else
      [line_item.line_price - (@discount_amount * line_item.quantity), Money.zero].max
    end

    line_item.change_line_price(new_line_price, message: @discount_message)
  end
end

# ================================================================
# DiscountLoop
#
# Loops through the supplied line items and discounts the supplied
# number of items by the supplied discount.
# ================================================================
class DiscountLoop
  def initialize(discount_applicator)
    @discount_applicator = discount_applicator
  end

  def loop_items(cart, line_items, num_to_discount)
    line_items.each_with_index do |line_item|
      break if num_to_discount <= 0

      if line_item.quantity > num_to_discount
        split_line_item = line_item.split(take: num_to_discount)
        @discount_applicator.apply(split_line_item)
        position = cart.line_items.find_index(line_item)
        cart.line_items.insert(position + 1, split_line_item)
        break
      else
        @discount_applicator.apply(line_item)
        num_to_discount -= line_item.quantity
      end
    end
  end
end

# ================================================================
# BundleDiscountCampaign
#
# If the entered bundle is present, the entered discount is
# applied to each item in the bundle.
# ================================================================
class BundleDiscountCampaign
  def initialize(campaigns)
    @campaigns = campaigns
  end

  def run(cart)
    @campaigns.each do |campaign|
      bundle_selector = BundleSelector.new(campaign[:bundle_items])
      bundle_items = bundle_selector.build(cart)

      next if bundle_items.any? do |product_id, product_info|
        product_info[:total_quantity] < product_info[:quantity_needed]
      end

      num_bundles = bundle_items.map do |product_id, product_info|
        (product_info[:total_quantity] / product_info[:quantity_needed])
      end

      num_bundles = num_bundles.min.floor

      discount_applicator = DiscountApplicator.new(
        campaign[:discount_type],
        campaign[:discount_amount],
        campaign[:discount_message]
      )

      discount_loop = DiscountLoop.new(discount_applicator)

      bundle_items.each do |product_id, product_info|
        discount_loop.loop_items(
          cart,
          product_info[:cart_items],
          (product_info[:quantity_needed] * num_bundles),
        )
      end
    end
  end
end

CAMPAIGNS = [
  BundleDiscountCampaign.new(BUNDLE_DISCOUNTS),
]

CAMPAIGNS.each do |campaign|
  campaign.run(Input.cart)
end

Output.cart = Input.cart
