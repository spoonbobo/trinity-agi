# Trinity Site

Marketing site and documentation for Trinity.

## Local development

```bash
npm install
npm run dev
```

Open `http://localhost:3000`.

## Build

```bash
npm run build
npm run start
```

## Content model

- Translation content lives in `src/i18n/translations.ts`
- Locale provider lives in `src/i18n/context.tsx`
- Main sections are in `src/components/*`

Keep language broad and system-oriented (not limited to "building apps").
