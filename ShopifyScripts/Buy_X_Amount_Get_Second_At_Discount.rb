# ================================ Customizable Settings ================================
# ================================================================
# Buy X, Get Y For Z Discount
#
# Buy a certain number of matching items, get a certain number
# of the same matching items with the entered discount applied. For
# example:
#
#   "Buy 2 products tagged with 'tag', get another product
#    tagged with 'tag' for 10% off"
#
#   - 'product_selector_match_type' determines whether we look for
#     products that do or don't match the entered selectors. Can
#     be:
#       - ':include' to check if the product does match
#       - ':exclude' to make sure the product doesn't match
#   - 'product_selector_type' determines how eligible products
#     will be identified. Can be either:
#       - ':tag' to find products by tag
#       - ':type' to find products by type
#       - ':vendor' to find products by vendor
#       - ':product_id' to find products by ID
#       - ':variant_id' to find products by variant ID
#       - ':subscription' to find subscription products
#       - ':all' for all products
#   - 'product_selectors' is a list of identifiers (from above) for
#     qualifying products. Product/Variant ID lists should only
#     contain numbers (ie. no quotes). If ':all' is used, this
#     can also be 'nil'.
#   - 'quantity_to_buy' is the number of products needed to
#     qualify
#   - 'quantity_to_discount' is the number of products to discount
#   - 'discount_type' is the type of discount to provide. Can be
#     either:
#       - ':percent'
#       - ':dollar'
#   - 'discount_amount' is the percentage/dollar discount to
#     apply (per item)
#   - 'discount_message' is the message to show when a discount
#     is applied
#
# Something to note for the case of running multiple offers is
# that there shouldn't be any overlap between product selection
# as this can lead to extra discounting. For example, you should
# NOT offer "Buy 1 Product X, get 1 50% off", as well as "Buy 2
# Product X, get 1 free"
# ================================================================
BUY_X_GET_Y_FOR_Z = [
  {
    product_selector_match_type: :include,
    product_selector_type: :all,
    product_selectors: nil,
    quantity_to_buy: 1,
    quantity_to_discount: 1,
    discount_type: :percent,
    discount_amount: 50,
    discount_message: 'Buy one item, get the second 50% off!',
  },
]

# ================================ Script Code (do not edit) ================================
# ================================================================
# ProductSelector
#
# Finds matching products by the entered criteria.
# ================================================================
class ProductSelector
  def initialize(match_type, selector_type, selectors)
    @match_type = match_type
    @comparator = match_type == :include ? 'any?' : 'none?'
    @selector_type = selector_type
    @selectors = selectors
  end

  def match?(line_item)
    if self.respond_to?(@selector_type)
      self.send(@selector_type, line_item)
    else
      raise RuntimeError.new('Invalid product selector type')
    end
  end

  def tag(line_item)
    product_tags = line_item.variant.product.tags.map { |tag| tag.downcase.strip }
    @selectors = @selectors.map { |selector| selector.downcase.strip }
    (@selectors & product_tags).send(@comparator)
  end

  def type(line_item)
    @selectors = @selectors.map { |selector| selector.downcase.strip }
    (@match_type == :include) == @selectors.include?(line_item.variant.product.product_type.downcase.strip)
  end

  def vendor(line_item)
    @selectors = @selectors.map { |selector| selector.downcase.strip }
    (@match_type == :include) == @selectors.include?(line_item.variant.product.vendor.downcase.strip)
  end

  def product_id(line_item)
    (@match_type == :include) == @selectors.include?(line_item.variant.product.id)
  end

  def variant_id(line_item)
    (@match_type == :include) == @selectors.include?(line_item.variant.id)
  end

  def subscription(line_item)
    !line_item.selling_plan_id.nil?
  end

  def all(line_item)
    true
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
# BuyXGetYForZCampaign
#
# Buy a certain number of matching items, get a certain number
# of the same matching items with the entered discount applied.
# ================================================================
class BuyXGetYForZCampaign
  def initialize(campaigns)
    @campaigns = campaigns
  end

  def run(cart)
    @campaigns.each do |campaign|
      product_selector = ProductSelector.new(
        campaign[:product_selector_match_type],
        campaign[:product_selector_type],
        campaign[:product_selectors],
      )

      eligible_items = cart.line_items.select { |line_item| product_selector.match?(line_item) }

      next if eligible_items.nil?

      eligible_items = eligible_items.sort_by { |line_item| -line_item.variant.price }
      quantity_to_buy = campaign[:quantity_to_buy]
      quantity_to_discount = campaign[:quantity_to_discount]
      bundle_size = quantity_to_buy + quantity_to_discount
      number_of_bundles = (eligible_items.map(&:quantity).reduce(0, :+) / bundle_size).floor
      number_of_discountable_items = number_of_bundles * quantity_to_discount

      next unless number_of_discountable_items > 0

      discount_applicator = DiscountApplicator.new(
        campaign[:discount_type],
        campaign[:discount_amount],
        campaign[:discount_message]
      )

      self.loop_items(
        discount_applicator, cart, eligible_items, number_of_discountable_items, quantity_to_buy, quantity_to_discount
      )
    end
  end

  def loop_items(discount_applicator, cart, line_items, num_to_discount, quantity_to_buy, quantity_to_discount)
    surplus = 0
    bundle_size = quantity_to_buy + quantity_to_discount

    line_items.each do |line_item|
      line_quantity = line_item.quantity + surplus

      if line_quantity > quantity_to_buy
        bundles_per_line = (line_quantity / bundle_size).floor
        take_quantity = bundles_per_line * quantity_to_discount
        surplus += (line_quantity - (bundle_size * bundles_per_line))

        if line_item.quantity > take_quantity
          discount_item = line_item.split(take: take_quantity)
          discount_applicator.apply(discount_item)
          position = cart.line_items.find_index(line_item)
          cart.line_items.insert(position + 1, discount_item)
          num_to_discount -= take_quantity
        else
          discount_applicator.apply(line_item)
          num_to_discount -= line_item.quantity
        end
      else
        surplus += line_quantity
      end

      break if num_to_discount <= 0
    end
  end
end

CAMPAIGNS = [
  BuyXGetYForZCampaign.new(BUY_X_GET_Y_FOR_Z),
]

CAMPAIGNS.each do |campaign|
  campaign.run(Input.cart)
end

Output.cart = Input.cart