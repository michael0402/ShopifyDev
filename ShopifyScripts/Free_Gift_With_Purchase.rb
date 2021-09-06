# ================================ Customizable Settings ================================
# ================================================================
# Spend $X, get Product Y for Z Discount
#
# If the cart total is greater than (or equal to) the entered
# threshold (less the discounted amount), the entered number of
# matching items is discounted by the entered amount.
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
#   - 'product_selectors' is a list of identifiers (from above)
#     for qualifying products. Product/Variant ID lists should
#     only contain numbers (ie. no quotes). If ':all' is used,
#     this can also be 'nil'.
#   - 'threshold' is the dollar amount needed to spend to qualify
#   - 'quantity_to_discount' is the number of items to discount
#     if qualified
#   - 'discount_type' is the type of discount to provide. Can be
#     either:
#       - ':percent'
#       - ':dollar'
#   - 'discount_amount' is the percentage/dollar discount to
#     apply (per item)
#   - 'discount_message' is the message to show when a discount
#     is applied
# ================================================================
SPENDX_GETY_FORZ = [
  {
    product_selector_match_type: :include,
    product_selector_type: :product_id,
    product_selectors: [1234567890123],
    threshold: 75,
    quantity_to_discount: 1,
    discount_type: :percent,
    discount_amount: 100,
    discount_message: 'Spend $75 or more and get a free Product X!',
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
    line_items.each do |line_item|
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
# SpendXGetYForZCampaign
#
# If the cart total is greater than (or equal to) the entered
# threshold (less the discounted amount), the entered number of
# matching items is discounted by the entered amount.
# ================================================================
class SpendXGetYForZCampaign
  def initialize(campaigns)
    @campaigns = campaigns
  end

  def run(cart)
    @campaigns.each do |campaign|
      threshold = Money.new(cents: 100) * campaign[:threshold]

      next if cart.subtotal_price < threshold

      product_selector = ProductSelector.new(
        campaign[:product_selector_match_type],
        campaign[:product_selector_type],
        campaign[:product_selectors],
      )

      eligible_items = cart.line_items.select { |line_item| product_selector.match?(line_item) }

      next if eligible_items.nil?

      eligible_items = eligible_items.sort_by { |line_item| line_item.variant.price }
      num_to_discount = campaign[:quantity_to_discount]
      cart_total = cart.subtotal_price

      eligible_items.each do |line_item|
        break if num_to_discount <= 0

        if line_item.quantity > num_to_discount
          cart_total -= line_item.variant.price * num_to_discount
          break
        else
          cart_total -= line_item.line_price
          num_to_discount -= line_item.quantity
        end
      end

      next if cart_total < threshold

      discount_applicator = discount_applicator = DiscountApplicator.new(
        campaign[:discount_type],
        campaign[:discount_amount],
        campaign[:discount_message]
      )

      discount_loop = DiscountLoop.new(discount_applicator)
      discount_loop.loop_items(cart, eligible_items, campaign[:quantity_to_discount])
    end
  end
end

CAMPAIGNS = [
  SpendXGetYForZCampaign.new(SPENDX_GETY_FORZ),
]

CAMPAIGNS.each do |campaign|
  campaign.run(Input.cart)
end

Output.cart = Input.cart