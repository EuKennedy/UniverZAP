<script setup>
import WoocommerceAPI from 'dashboard/api/integrations/woocommerce';
import StoreOrdersCard from './StoreOrdersCard.vue';

// The card reads the API singleton; the story answers it with a customer of
// 12 orders, split in pages of 10 like the real endpoint.
const item = (name, quantity, total, image) => ({
  name,
  quantity,
  total,
  image,
});
const orders = Array.from({ length: 12 }, (_, i) => ({
  id: i + 1,
  number: String(1052 - i),
  status: ['pending', 'processing', 'completed', 'completed', 'refunded'][
    i % 5
  ],
  currency: 'BRL',
  total: [189.9, 97.4, 254.0, 59.9, 120.5][i % 5],
  payment_method_title: i % 2 ? 'Cartão de crédito' : 'Pix',
  payment_url: 'https://lizzon.com.br/pagar',
  items: [
    item('Booster Ativador de Cachos 500ml', 2, '159.80'),
    item('Máscara Hidratação Profunda 1kg', 1, '30.10'),
  ].slice(0, (i % 2) + 1),
  tracking: i % 5 === 2 ? { code: 'QB123456789BR', carrier: 'Correios' } : {},
  placed_at: new Date(Date.UTC(2026, 9, 20 - i * 9, 13)).toISOString(),
  paid_at:
    i % 5 ? new Date(Date.UTC(2026, 9, 20 - i * 9, 14)).toISOString() : null,
  admin_url: `https://lizzon.com.br/wp-admin/post.php?post=${i + 1}&action=edit`,
}));

WoocommerceAPI.getOrders = async (contactId, page = 1) => ({
  data: {
    connected: true,
    store_name: 'lizzon.com.br',
    customer: {
      customer_name: 'Rosana Rita',
      customer_email: 'rosana@example.com',
    },
    metrics: {
      orders_count: 9,
      total_spent: 1287.6,
      average_ticket: 143.07,
      last_order_at: orders[0].placed_at,
    },
    orders: orders.slice((page - 1) * 10, page * 10),
    has_more: page * 10 < orders.length,
    total_count: orders.length,
  },
});
</script>

<template>
  <Story
    title="Components/Store/StoreOrdersCard"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Customer with order history">
      <div class="p-4 w-80 bg-n-background">
        <StoreOrdersCard :contact-id="1" />
      </div>
    </Variant>
  </Story>
</template>
