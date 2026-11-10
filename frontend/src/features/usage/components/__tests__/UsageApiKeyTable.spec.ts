import { afterEach, describe, expect, it } from 'vitest'
import { createApp, type App } from 'vue'
import UsageApiKeyTable from '../UsageApiKeyTable.vue'
import type { ApiKeyStatsItem } from '../../types'

const mountedApps: Array<{ app: App, root: HTMLElement }> = []

function mountTable(
  data: ApiKeyStatsItem[],
  options: { isLoading?: boolean, hasError?: boolean } = {},
): HTMLElement {
  const root = document.createElement('div')
  document.body.appendChild(root)
  const app = createApp(UsageApiKeyTable, { data, ...options })
  app.mount(root)
  mountedApps.push({ app, root })
  return root
}

afterEach(() => {
  for (const { app, root } of mountedApps.splice(0)) {
    app.unmount()
    root.remove()
  }
})

describe('UsageApiKeyTable', () => {
  it('renders key usage metrics and cost share', () => {
    const root = mountTable([
      {
        id: 'key-1',
        name: 'Production',
        requests: 12,
        tokens: 1_250_000,
        cost: 0.75,
      },
      {
        id: 'key-2',
        name: 'Testing',
        requests: 3,
        tokens: 250_000,
        cost: 0.25,
      },
    ])

    expect(root.textContent).toContain('按密钥分析')
    expect(root.querySelector('thead')?.textContent).not.toContain('#')
    expect(root.textContent).toContain('Production')
    expect(root.textContent).toContain('1.25M')
    expect(root.textContent).toContain('$0.75')
    expect(root.querySelector('[data-testid="api-key-cost-share-key-1"]')?.textContent?.trim())
      .toBe('75.0%')
    expect(root.querySelector('[data-testid="api-key-cost-share-key-2"]')?.textContent?.trim())
      .toBe('25.0%')
  })

  it('shows an empty state when no key has usage', () => {
    const root = mountTable([])

    expect(root.textContent).toContain('暂无密钥使用数据')
  })

  it('shows a loading state while the key aggregation is pending', () => {
    const root = mountTable([], { isLoading: true })

    expect(root.textContent).toContain('正在加载密钥使用数据')
    expect(root.textContent).not.toContain('暂无密钥使用数据')
  })

  it('shows an error state when the key aggregation fails', () => {
    const root = mountTable([], { hasError: true })

    expect(root.textContent).toContain('密钥使用数据加载失败')
    expect(root.textContent).not.toContain('暂无密钥使用数据')
  })
})
