# RSR MESHI 2026

RSR2026公式出店情報を、メニュー単位で検索できるモバイル向け非公式ツールです。

## ローカル確認

```powershell
npx serve .
```

依存関係のない静的サイトなので、GitHub Pages / Cloudflare Pages / Netlify / Vercel などへフォルダーをそのまま配置できます。HTTPS環境では現在地機能が利用できます。

## データ更新

`official-food-raw.html` を公式ページから更新した後、次を実行します。

```powershell
python scripts/extract_foods.py
```

出典: https://rsr.wess.co.jp/2026/site/food_shop/
