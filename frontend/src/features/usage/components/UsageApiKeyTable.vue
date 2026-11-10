<template>
  <Card
    class="overflow-hidden flex flex-col"
    data-testid="usage-api-key-analysis"
  >
    <div class="px-3 py-2 border-b flex-shrink-0">
      <h3 class="text-sm font-medium">
        按密钥分析
      </h3>
    </div>
    <div class="overflow-auto max-h-[320px]">
      <Table class="text-sm">
        <TableHeader>
          <TableRow>
            <TableHead class="h-8 px-2">
              密钥
            </TableHead>
            <TableHead class="h-8 px-2 text-right">
              请求数
            </TableHead>
            <TableHead class="h-8 px-2 text-right">
              Token
            </TableHead>
            <TableHead class="h-8 px-2 text-right">
              费用
            </TableHead>
            <TableHead class="h-8 px-2 text-right">
              费用占比
            </TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow v-if="isLoading && data.length === 0">
            <TableCell
              :colspan="5"
              class="py-6 px-2"
            >
              <span class="flex items-center justify-center gap-2 text-muted-foreground">
                <LoaderCircle class="h-4 w-4 animate-spin" />
                正在加载密钥使用数据...
              </span>
            </TableCell>
          </TableRow>
          <TableRow v-else-if="hasError && data.length === 0">
            <TableCell
              :colspan="5"
              class="text-center py-6 text-muted-foreground px-2"
            >
              密钥使用数据加载失败，请稍后重试
            </TableCell>
          </TableRow>
          <TableRow v-else-if="data.length === 0">
            <TableCell
              :colspan="5"
              class="text-center py-6 text-muted-foreground px-2"
            >
              暂无密钥使用数据
            </TableCell>
          </TableRow>
          <TableRow
            v-for="item in data"
            :key="item.id"
          >
            <TableCell class="font-medium py-2 px-2">
              <span
                class="block max-w-[360px] truncate"
                :title="item.name"
              >
                {{ item.name }}
              </span>
            </TableCell>
            <TableCell class="text-right tabular-nums py-2 px-2">
              {{ item.requests }}
            </TableCell>
            <TableCell class="text-right tabular-nums py-2 px-2">
              {{ formatTokens(item.tokens) }}
            </TableCell>
            <TableCell class="text-right text-primary font-medium tabular-nums py-2 px-2">
              {{ formatCurrency(item.cost) }}
            </TableCell>
            <TableCell class="text-right py-2 px-2">
              <div class="flex items-center justify-end gap-2">
                <span
                  class="text-muted-foreground tabular-nums text-xs"
                  :data-testid="`api-key-cost-share-${item.id}`"
                >
                  {{ formatCostShare(item.cost) }}
                </span>
                <div class="h-1.5 w-16 overflow-hidden rounded-full bg-muted">
                  <div
                    class="h-full rounded-full bg-primary"
                    :style="{ width: `${costSharePercent(item.cost)}%` }"
                  />
                </div>
              </div>
            </TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>
  </Card>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { LoaderCircle } from 'lucide-vue-next'
import Card from '@/components/ui/card.vue'
import Table from '@/components/ui/table.vue'
import TableHeader from '@/components/ui/table-header.vue'
import TableBody from '@/components/ui/table-body.vue'
import TableRow from '@/components/ui/table-row.vue'
import TableHead from '@/components/ui/table-head.vue'
import TableCell from '@/components/ui/table-cell.vue'
import { formatCurrency, formatTokens } from '@/utils/format'
import type { ApiKeyStatsItem } from '../types'

const props = withDefaults(defineProps<{
  data: ApiKeyStatsItem[]
  isLoading?: boolean
  hasError?: boolean
}>(), {
  isLoading: false,
  hasError: false,
})

const totalCost = computed(() => props.data.reduce(
  (total, item) => total + Math.max(0, item.cost),
  0
))

function costSharePercent(cost: number): number {
  if (totalCost.value <= 0) return 0
  return Math.min(100, Math.max(0, Math.max(0, cost) / totalCost.value * 100))
}

function formatCostShare(cost: number): string {
  if (totalCost.value <= 0) return '-'
  return `${costSharePercent(cost).toFixed(1)}%`
}
</script>
