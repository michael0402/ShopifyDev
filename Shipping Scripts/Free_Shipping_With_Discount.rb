min_discount_order_amount = Money.new(cents:100)*70
total=Input.cart.subtotal_price
if Input.cart.shipping_address.country_code == "CA"
  total=total*1.165
end
message = "Free shipping for orders over $70"

if total > min_discount_order_amount
  discount = 1
else
  discount = 0
end


Input.shipping_rates.each do |shipping_rate|
  if shipping_rate.name == "Free Shipping"
    break
  elsif shipping_rate.name == "UPS® Standard" && Input.cart.shipping_address.country_code == "US" && discount == 1
    shipping_rate.apply_discount(shipping_rate.price, message: message)
  elsif shipping_rate.name == "Regular Parcel" && Input.cart.shipping_address.country_code == "CA" && discount == 1
    shipping_rate.apply_discount(shipping_rate.price, message: message)
  end
end
  

Output.shipping_rates = Input.shipping_rates