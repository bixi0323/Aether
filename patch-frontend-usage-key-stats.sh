#!/usr/bin/env bash
# Publish the usage-page API-key analysis table into an existing Aether frontend
# dist without running a full Vite/Rollup build on low-resource hosts.
set -euo pipefail

DIR="${1:-/opt/aether/frontend-dist}"
[[ -f "$DIR/index.html" ]] || { echo "frontend index not found in $DIR" >&2; exit 1; }

entry_path="$(python3 - "$DIR/index.html" <<'PY'
import pathlib
import re
import sys

html = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'<script\b[^>]*\btype="module"[^>]*\bsrc="/[^"/]+/(index-[^"/?]+\.js)', html)
if match is None:
    raise SystemExit('module entry not found in index.html')
print(match.group(0).split('src="', 1)[1].strip('"'))
PY
)"
entry_name="$(basename "$entry_path")"
current_bundle_name="$(basename "$(dirname "$entry_path")")"
current_bundle="$DIR/$current_bundle_name"
[[ -d "$current_bundle" ]] || { echo "current bundle not found: $current_bundle" >&2; exit 1; }

usage_chunk="$(find "$current_bundle" -maxdepth 1 -type f -name 'Usage-*.js' -print -quit)"
[[ -n "$usage_chunk" ]] || { echo "Usage chunk not found in $current_bundle" >&2; exit 1; }

python3 - "$usage_chunk" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()

marker = 'AetherUsageApiKeyTable'
if marker in source:
    print('usage key table patch already present:', path)
    raise SystemExit(0)

live_api_old = 'getUsageByApiFormat(t,e){return $(this,null,function*(){return this.getUsageAggregation("api_format",t,e)})},getUserUsage'
if live_api_old in source:
    live_api_new = (
        'getUsageByApiFormat(t,e){return $(this,null,function*(){return this.getUsageAggregation("api_format",t,e)})},'
        'getUsageByApiKey(t,e){return $(this,null,function*(){'
        'const i=Jt(X(X({},t),{provider_name:t==null?void 0:t.provider,provider:void 0,include_inactive:!0,metric:"cost",order:"desc",limit:100,offset:0}));'
        'const u=`usage-aggregation-api-key-${JSON.stringify(i)}${e!=null&&e.skipCache?":fresh":""}`;'
        'return sa(u,()=>$(null,null,function*(){return(yield Ee.get("/api/admin/stats/leaderboard/api-keys",{params:i,timeout:Ea})).data.items}),e!=null&&e.skipCache?0:3e5)})},'
        'getUserUsage'
    )
    live_ref_old = 'q=O([]),z=O([]),C=O(0)'
    live_ref_new = 'q=O([]),apiKeyStats=O([]),z=O([]),C=O(0)'
    live_clear_old = 'q.value=[],ee.value=[]'
    live_clear_new = 'q.value=[],apiKeyStats.value=[],ee.value=[]'
    live_load_old = 'catch(E){if(j!==x)return!0;W(E)}return o}const J=yield Gt.getUsage(U);'
    live_load_new = (
        'catch(E){if(j!==x)return!0;W(E)}'
        'try{const E=yield Ye.getUsageByApiKey(U,P);if(j!==x)return!0;'
        'apiKeyStats.value=E.map(M=>be(X({},M),{name:(M.name==null?void 0:M.name.trim())||M.id}))}'
        'catch(E){if(j!==x)return!0;W(E)}'
        'return o}const J=yield Gt.getUsage(U);'
    )
    live_component = r'''AetherUsageApiKeyTable=Se({
  __name:"UsageApiKeyTable",
  props:{data:{type:Array,default:()=>[]}},
  setup(t){
    const e=t;
    const totalCost=()=>e.data.reduce((sum,item)=>sum+Math.max(0,Number(item.cost)||0),0);
    const costShare=(cost)=>{const total=totalCost();return total>0?Math.min(100,Math.max(0,(Math.max(0,Number(cost)||0)/total)*100)):0};
    const formatShare=(cost)=>totalCost()>0?costShare(cost).toFixed(1)+"%":"-";
    return (i,u)=>(r(),A(ja,{class:"overflow-hidden flex flex-col"},{default:v(()=>[
      g("div",{class:"px-3 py-2 border-b flex-shrink-0"},[g("h3",{class:"text-sm font-medium"},p("按密钥分析"),1)]),
      g("div",{class:"overflow-auto max-h-[320px]"},[
        g("table",{class:"w-full caption-bottom text-sm"},[
          g("thead",{class:"[&_tr]:border-b"},[
            g("tr",{class:"border-b transition-colors hover:bg-muted/50"},[
              g("th",{class:"h-8 w-12 px-2 text-right align-middle font-medium text-muted-foreground"},[D("#",-1)]),
              g("th",{class:"h-8 px-2 text-left align-middle font-medium text-muted-foreground"},[D("密钥",-1)]),
              g("th",{class:"h-8 px-2 text-right align-middle font-medium text-muted-foreground"},[D("请求数",-1)]),
              g("th",{class:"h-8 px-2 text-right align-middle font-medium text-muted-foreground"},[D("Token",-1)]),
              g("th",{class:"h-8 px-2 text-right align-middle font-medium text-muted-foreground"},[D("费用",-1)]),
              g("th",{class:"h-8 px-2 text-right align-middle font-medium text-muted-foreground"},[D("费用占比",-1)])
            ])
          ]),
          g("tbody",{class:"[&_tr:last-child]:border-0"},[
            e.data.length===0?g("tr",null,[g("td",{colspan:6,class:"p-2 align-middle text-center py-6 text-muted-foreground"},[D("暂无密钥使用数据",-1)])]):w("",!0),
            (r(!0),k(re,null,xe(e.data,n=>g("tr",{key:n.id,class:"border-b transition-colors hover:bg-muted/50"},[
              g("td",{class:"p-2 align-middle text-right text-muted-foreground tabular-nums"},[D(p(n.rank),-1)]),
              g("td",{class:"p-2 align-middle font-medium"},[g("span",{class:"block max-w-[360px] truncate"},[D(p(n.name),-1)])]),
              g("td",{class:"p-2 align-middle text-right tabular-nums"},[D(p(n.requests),-1)]),
              g("td",{class:"p-2 align-middle text-right tabular-nums"},[D(p(a(je)(n.tokens)),-1)]),
              g("td",{class:"p-2 align-middle text-right font-medium text-primary tabular-nums"},[D(p(a(bt)(n.cost)),-1)]),
              g("td",{class:"p-2 align-middle text-right"},[g("div",{class:"flex items-center justify-end gap-2"},[
                g("span",{class:"text-xs text-muted-foreground tabular-nums"},[D(p(formatShare(n.cost)),-1)]),
                g("div",{class:"h-1.5 w-16 overflow-hidden rounded-full bg-muted"},[
                  g("div",{class:"h-full rounded-full bg-primary",style:{width:costShare(n.cost)+"%"}},null,4)
                ])
              ])])
            ])),128))
          ])
        ])
      ])
    ]),_:1}))
  }
}),ro=Se({__name:"UsageProviderTable"'''
    live_replacements = [
        ('live API method', live_api_old, live_api_new),
        ('live stats ref', live_ref_old, live_ref_new),
        ('live stats reset', live_clear_old, live_clear_new),
        ('live stats load', live_load_old, live_load_new),
        ('live stats return', 'apiFormatStats:q,currentRecords:z', 'apiFormatStats:q,apiKeyStats:apiKeyStats,currentRecords:z'),
        ('live view destructure', 'apiFormatStats:m,currentRecords:o', 'apiFormatStats:m,apiKeyStats:keyStats,currentRecords:o'),
        ('live key table component', '),ro=Se({__name:"UsageProviderTable"', '),' + live_component),
        ('live admin layout', 'h.value?(r(),k("div",Pr,[b(za,', 'h.value?(r(),k("div",Pr,[b(AetherUsageApiKeyTable,{data:a(keyStats),style:{gridColumn:"1 / -1"}},null,8,["data"]),b(za,'),
    ]
    for label, old, new in live_replacements:
        count = source.count(old)
        if count != 1:
            raise SystemExit(f'{label} marker count is {count}, expected 1')
        source = source.replace(old, new, 1)
    path.write_text(source)
    print('patched live bundle:', path)
    raise SystemExit(0)

api_old = 'getUsageByApiFormat(o,s){return I(this,null,function*(){return this.getUsageAggregation("api_format",o,s)})},getUserUsage'
api_new = (
    'getUsageByApiFormat(o,s){return I(this,null,function*(){return this.getUsageAggregation("api_format",o,s)})},'
    'getUsageByApiKey(o,s){return I(this,null,function*(){'
    'const i=Yt(ne(ne({},o),{provider_name:o==null?void 0:o.provider,provider:void 0,include_inactive:!0,metric:"cost",order:"desc",limit:100,offset:0}));'
    'const g=`usage-aggregation-api-key-${JSON.stringify(i)}${s!=null&&s.skipCache?":fresh":""}`;'
    'return Xt(g,()=>I(null,null,function*(){return(yield at.get("/api/admin/stats/leaderboard/api-keys",{params:i,timeout:Na})).data.items}),s!=null&&s.skipCache?0:3e5)})},'
    'getUserUsage'
)

ref_old = 'z=N([]),L=N([]),q=N(0),W=N(void 0)'
ref_new = 'z=N([]),apiKeyStats=N([]),L=N([]),q=N(0),W=N(void 0)'
clear_old = 'h.value=ta(),D.value=[],w.value=[],z.value=[],Ae.value=[],le.value=[]'
clear_new = 'h.value=ta(),D.value=[],w.value=[],z.value=[],apiKeyStats.value=[],Ae.value=[],le.value=[]'
load_old = 'catch(E){if(B!==x)return!0;ue(E)}return C}const ee=yield Bt.getUsage(F);'
load_new = (
    'catch(E){if(B!==x)return!0;ue(E)}'
    'try{const E=yield ft.getUsageByApiKey(F,ie);if(B!==x)return!0;'
    'apiKeyStats.value=E.map(P=>Be(ne({},P),{name:(P.name==null?void 0:P.name.trim())||P.id}))}'
    'catch(E){if(B!==x)return!0;ue(E)}'
    'return C}const ee=yield Bt.getUsage(F);'
)
return_old = 'apiFormatStats:z,currentRecords:L'
return_new = 'apiFormatStats:z,apiKeyStats:apiKeyStats,currentRecords:L'
destructure_old = 'apiFormatStats:ue,currentRecords:E'
destructure_new = 'apiFormatStats:ue,apiKeyStats:keyStats,currentRecords:E'

component = r'''AetherUsageApiKeyTable=nt({
  __name:"UsageApiKeyTable",
  props:{data:{type:Array,default:()=>[]}},
  setup(o){
    const{legacyT:s}=vt();
    const totalCost=()=>o.data.reduce((sum,item)=>sum+Math.max(0,Number(item.cost)||0),0);
    const costShare=(cost)=>{const total=totalCost();return total>0?Math.min(100,Math.max(0,(Math.max(0,Number(cost)||0)/total)*100)):0};
    const formatShare=(cost)=>totalCost()>0?costShare(cost).toFixed(1)+"%":"-";
    return (i,g)=>(l(),A(Vt,{class:"overflow-hidden flex flex-col"},{default:c(()=>[
      m("div",{class:"px-3 py-2 border-b flex-shrink-0"},[
        m("h3",{class:"text-sm font-medium"},u(t(s)("按密钥分析")),1)
      ]),
      m("div",{class:"overflow-auto max-h-[320px]"},[
        m("table",{class:"w-full caption-bottom text-sm"},[
          m("thead",{class:"[&_tr]:border-b"},[
            m("tr",{class:"border-b transition-colors hover:bg-muted/50"},[
              m("th",{class:"h-8 w-12 px-2 text-right align-middle font-medium text-muted-foreground"},u("#"),1),
              m("th",{class:"h-8 px-2 text-left align-middle font-medium text-muted-foreground"},u(t(s)("密钥")),1),
              m("th",{class:"h-8 px-2 text-right align-middle font-medium text-muted-foreground"},u(t(s)("请求数")),1),
              m("th",{class:"h-8 px-2 text-right align-middle font-medium text-muted-foreground"},u("Token"),1),
              m("th",{class:"h-8 px-2 text-right align-middle font-medium text-muted-foreground"},u(t(s)("费用")),1),
              m("th",{class:"h-8 px-2 text-right align-middle font-medium text-muted-foreground"},u(t(s)("费用占比")),1)
            ])
          ]),
          m("tbody",{class:"[&_tr:last-child]:border-0"},[
            i.data.length===0?m("tr",null,[m("td",{colspan:6,class:"p-2 align-middle text-center py-6 text-muted-foreground"},u(t(s)("暂无密钥使用数据")),1)]):k("",!0),
            (l(!0),b(de,null,Ve(i.data,v=>m("tr",{key:v.id,class:"border-b transition-colors hover:bg-muted/50"},[
              m("td",{class:"p-2 align-middle text-right text-muted-foreground tabular-nums"},u(v.rank),1),
              m("td",{class:"p-2 align-middle font-medium"},[m("span",{class:"block max-w-[360px] truncate"},u(v.name),1)]),
              m("td",{class:"p-2 align-middle text-right tabular-nums"},u(v.requests),1),
              m("td",{class:"p-2 align-middle text-right tabular-nums"},u(t(xe)(v.tokens)),1),
              m("td",{class:"p-2 align-middle text-right font-medium text-primary tabular-nums"},u(t(st)(v.cost)),1),
              m("td",{class:"p-2 align-middle text-right"},[m("div",{class:"flex items-center justify-end gap-2"},[
                m("span",{class:"text-xs text-muted-foreground tabular-nums"},u(formatShare(v.cost)),1),
                m("div",{class:"h-1.5 w-16 overflow-hidden rounded-full bg-muted"},[
                  m("div",{class:"h-full rounded-full bg-primary",style:{width:costShare(v.cost)+"%"}},null,4)
                ])
              ])])
            ])),128))
          ])
        ])
      ])
    ]),_:1}))
  }
}),Nn={class:"px-3 py-2 border-b flex-shrink-0"}'''

render_old = 'w.value?(l(),b("div",_r,[p(t(Oa),{data:t(Z),"is-admin":t(D).canAccessAdmin}'
render_new = 'w.value?(l(),b("div",_r,[p(t(AetherUsageApiKeyTable),{data:t(keyStats),class:"lg:col-span-3"},null,8,["data"]),p(t(Oa),{data:t(Z),"is-admin":t(D).canAccessAdmin}'
component_old = '),Nn={class:"px-3 py-2 border-b flex-shrink-0"}'

replacements = [
    ('API method', api_old, api_new),
    ('stats ref', ref_old, ref_new),
    ('stats reset', clear_old, clear_new),
    ('stats load', load_old, load_new),
    ('stats return', return_old, return_new),
    ('view destructure', destructure_old, destructure_new),
    ('key table component', component_old, '),' + component),
    ('admin layout', render_old, render_new),
]

for label, old, new in replacements:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f'{label} marker count is {count}, expected 1')
    source = source.replace(old, new, 1)

path.write_text(source)
print('patched:', path)
PY

version="$({
  sha256sum < "$usage_chunk"
  sed -E 's#/assets[^/]*/#/assets/#g' "$DIR/index.html"
} | sha256sum | cut -c1-12)"
new_bundle_name="assets-usagekeys-$version"
new_bundle="$DIR/$new_bundle_name"

rm -rf "$new_bundle"
cp -a "$current_bundle" "$new_bundle"

python3 - "$new_bundle" "$current_bundle_name" "$new_bundle_name" <<'PY'
import pathlib
import sys

bundle = pathlib.Path(sys.argv[1])
old_name, new_name = sys.argv[2:]
for asset in bundle.iterdir():
    if not asset.is_file() or asset.suffix not in {'.js', '.css'}:
        continue
    text = asset.read_text()
    updated = text.replace(old_name, new_name)
    if updated != text:
        asset.write_text(updated)
PY

python3 - "$DIR/index.html" "$current_bundle_name" "$new_bundle_name" "$entry_name" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
old_name, new_name, entry_name = sys.argv[2:]
html = path.read_text().replace(old_name, new_name)
path.write_text(html)
PY

find "$new_bundle" -type f -exec chmod 644 {} +
find "$new_bundle" -type d -exec chmod 755 {} +
node --input-type=module --check < "$new_bundle/$entry_name"
node --input-type=module --check < "$new_bundle/$(basename "$usage_chunk")"
printf 'published frontend bundle: %s\n' "$new_bundle"
