Shopify Scripts are customizations written in Ruby that allow you to create personalized customer experiences. Using line item, shipping, and payment scripts you can implement custom logic and tailor the user experience during a customer’s checkout journey. Scripts are enabled on a store’s checkout by using the Script Editor app.

Shopify Scripts are written in a stripped-down version of Ruby, and work by receiving an “input” of the cart, customer, and shipping methods or payment gateways, run the script code to perform modifications, and then return the result as an “output” which is then applied to the cart or checkout. The Script Editor app hosts scripts you’ve created on Shopify’s servers, allowing them to affect the cart and checkout at a fundamental level without the need of third-party apps or externally hosted plugins.

There are three different types of Shopify Scripts:

1. Line item scripts affect line items in the cart and can change prices and grant discounts. Note: Theme modifications may be required to the show the discount amount or messages in the cart and checkout.
2. Shipping scripts interact with shipping, and can rename, show, hide, or reorder shipping methods and grant discounts on shipping rates.
3. Payment scripts interact with payments, and can rename, show, hide, or reorder payment gateways.

In this repo you will find a series of scripts which were developed to offer greater customization over a merchants store checkout.