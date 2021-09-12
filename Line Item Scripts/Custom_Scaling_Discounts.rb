discount_message = ""
discount = 0.999999999999  # It won't actually work with only 1 item in cart unless it calculates a different total, discount * 1 will simply not do anything
total_items = 0
Input.cart.line_items.each do |line_item|
  total_items += line_item.quantity
end

case total_items
  when 0
    discount_message = "Add something to your cart!"
  when 1
    discount_message = "Congratulations! You get FREE shipping with your order. Order one more item for FREE shipping & 40% off one item."
  when 2
    discount_message = "Congratulations! You get FREE shipping and 40% off one item. Order one more and we'll bump that up to 70% off one item!"
    discount = 0.6
  when 3
    discount_message = "Congratulations! You get FREE shipping and 70% off one item. Order one more and we'll bump that up to a FREE item!"
    discount = 0.3
  else
    discount_message = "Congratulations! You get FREE shipping and a FREE item. For every additional item you order, we will take 30% off the item."
    discount = 0
end

sorted_items = Input.cart.line_items.sort_by{|line_item| line_item.variant.price}
sorted_items.each do |line_item|
  # Discount only the cheapest item
  if line_item.quantity > 1
    discounted_item = line_item.split(take: 1)
    position = Input.cart.line_items.find_index(line_item)
    discounted_item.change_line_price(discounted_item.line_price * discount, message: discount_message)
    Input.cart.line_items.insert(position + 1, discounted_item)
  else
    line_item.change_line_price(line_item.line_price * discount, message: discount_message)
  end
  break
end

additionally_discounted_item_count = 0
while (total_items - additionally_discounted_item_count > 4) do
  sorted_items = Input.cart.line_items.sort_by{|line_item| line_item.variant.price}
  sorted_items.each do |line_item|
    if (line_item.line_price_changed?	== false)
      if line_item.quantity > 1
    
        how_many_to_take = 1
        while (how_many_to_take <= (total_items - additionally_discounted_item_count - 5) and (how_many_to_take < line_item.quantity)) do 
          how_many_to_take += 1
        end
        
        puts "quantity"
        puts line_item.quantity
        puts "how many to take"
        puts how_many_to_take
        
        if line_item.quantity == how_many_to_take
          line_item.change_line_price(line_item.line_price * 0.7, message: "30% off item")
          additionally_discounted_item_count += how_many_to_take
        else
          discounted_item = line_item.split(take: how_many_to_take)
          position = Input.cart.line_items.find_index(line_item)
          discounted_item.change_line_price(discounted_item.line_price * 0.7, message: "30% off item")
          Input.cart.line_items.insert(position + 1, discounted_item)
          additionally_discounted_item_count += how_many_to_take
        end
      else
        line_item.change_line_price(line_item.line_price * 0.7, message: "30% off item")
        additionally_discounted_item_count += 1
      end
      break
    end
  end
end

Output.cart = Input.cart