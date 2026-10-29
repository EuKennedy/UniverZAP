<script setup>
import { useI18n } from 'vue-i18n';
import WoocommerceAPI from 'dashboard/api/integrations/woocommerce';
import StoreOrdersCard from './StoreOrdersCard.vue';

// The card reads the API singleton; the story answers it with a customer of
// 14 orders, split in pages of 10 like the real endpoint, in the product's
// language.
useI18n().locale.value = 'pt_BR';

const item = (name, quantity) => ({ name, quantity, total: '49.90' });
const ITEMS = [
  item('Cortex Repair Restaurizze 300mL', 1),
  item('Shampoo Detox Express Carbon Intense 1L', 1),
  item('Colorizze: Coloração Creme Permanente 7.1', 3),
  item('Btx Blond Volume Control 1kg', 1),
];
const STATUSES = [
  'processing',
  'pending',
  'uvf-shipped',
  'completed',
  'refunded',
  'wc-delivered',
  'failed',
];
const orders = Array.from({ length: 14 }, (_, i) => ({
  id: i + 1,
  number: String(39341 - i * 311),
  status: STATUSES[i % STATUSES.length],
  currency: 'BRL',
  total: [189.9, 67.76, 418.0, 165.18, 59.9, 254.0, 97.4][i % 7],
  payment_method_title: i % 2 ? 'Cartão de crédito' : 'Pix',
  payment_url: 'https://lizzon.com.br/pagar',
  items: ITEMS.slice(0, (i % 4) + 1),
  tracking: i % 7 === 2 ? { code: 'QB123456789BR', carrier: 'Correios' } : {},
  placed_at: new Date(Date.UTC(2026, 9, 29 - i * 23, 13)).toISOString(),
  paid_at:
    i % 7 === 1
      ? null
      : new Date(Date.UTC(2026, 9, 29 - i * 23, 14)).toISOString(),
  admin_url: `https://lizzon.com.br/wp-admin/post.php?post=${i + 1}&action=edit`,
}));

WoocommerceAPI.getOrders = async (contactId, page = 1) => ({
  data: {
    connected: true,
    store_name: 'lizzon.com.br',
    customer: {
      customer_name: 'Miriane Dias Morais',
      customer_email: 'miriane@example.com',
    },
    metrics: {
      orders_count: 4,
      total_spent: 485.76,
      average_ticket: 121.44,
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
      <div class="p-4 w-[22rem] bg-n-background">
        <StoreOrdersCard :contact-id="1" />
      </div>
    </Variant>
  </Story>
</template>
