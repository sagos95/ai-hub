# Holst.so Board Data Export

Инструкция по извлечению данных (фреймы, стикеры, тексты и т.д.) из досок [Holst.so](https://app.holst.so) — Miro-подобного инструмента без публичного API.

## Принцип работы

Holst хранит содержимое доски в формате **Yjs CRDT** (v2). Данные можно получить через внутренний backup API, а затем распарсить библиотекой Yjs прямо в браузере.

### Архитектура данных

```
Yjs Document
├── objects    (Map) — все визуальные объекты: frame, sticker, arrow, simple-text, shape и т.д.
├── documents  (Map) — тексты объектов (id документа → текстовое содержимое)
├── usersIds   (Map) — пользователи
├── delete-events-metaStore (Map)
├── reactionsStore (Map)
└── task-card-statusesStore (Map)
```

**Связи:**
- Каждый объект в `objects` имеет `id`, `type`, `parentId` (вложенность во фрейм)
- Стикеры (`type: "sticker"`) ссылаются на текст через `documentId` → ключ в `documents`
- Фреймы (`type: "frame"`) содержат имя в поле `labelText`
- Дочерние объекты ссылаются на родителя через `parentId`

## Требования

- **Chrome DevTools MCP** (`chrome-devtools-mcp`) — для управления браузером
- Авторизованная сессия в Holst (через браузер MCP)

### Установка MCP

```bash
claude mcp add chrome-devtools -- npx chrome-devtools-mcp@latest
```

## Пошаговая инструкция для AI-агента

### Шаг 1: Открыть доску

```
navigate_page → url: https://app.holst.so/board/{BOARD_ID}
```

Если редирект на `/login` — пользователь должен авторизоваться вручную.

### Шаг 2: Получить список бэкапов через внутренний сервис

```javascript
// Найти backup-сервис в React DI-контейнере
const root = document.getElementById('root');
const containerKey = Object.keys(root).find(k => k.startsWith('__reactContainer'));
let fiber = root[containerKey];

let backupService = null;
function walk(f, d) {
  if (!f || d > 70 || backupService) return;
  let state = f.memoizedState;
  let si = 0;
  while (state && si < 20) {
    try {
      const ms = state.memoizedState;
      if (ms && ms.current && ms.current._providers) {
        let container = ms.current;
        while (container) {
          for (const o of (container.objs || [])) {
            if (o && o.getBackupList$) backupService = o;
          }
          container = container._parent;
        }
      }
    } catch(e) {}
    state = state.next;
    si++;
  }
  if (f.child) walk(f.child, d + 1);
  if (f.sibling) walk(f.sibling, d + 1);
}
walk(fiber, 0);
```

Вызвать список бэкапов:

```javascript
const boardId = '{BOARD_ID}';
const backups = await new Promise((resolve, reject) => {
  backupService.getBackupList$(boardId, true).subscribe({
    next: resolve,
    error: reject
  });
});
// backups[0] — самый свежий, содержит { id, date, encodeVersion }
```

### Шаг 3: Скачать и распарсить бэкап через Yjs

```javascript
// Скачать бэкап (encodeVersion=2 → server_provider_type="hud")
const latestBackup = backups[0];
const blob = await backupService.fetchBackup(latestBackup.id, latestBackup.encodeVersion);
const uint8 = new Uint8Array(await blob.arrayBuffer());

// Загрузить Yjs
const Y = await import('https://esm.sh/yjs@13.6.18');

// Распарсить (ВАЖНО: использовать applyUpdateV2, не applyUpdate)
const doc = new Y.Doc();
Y.applyUpdateV2(doc, uint8);
```

### Шаг 4: Извлечь данные

```javascript
const objects = doc.getMap('objects');
const documents = doc.getMap('documents');

// Собрать все объекты в массив
const allObjects = [];
objects.forEach((val, key) => {
  allObjects.push(val.toJSON ? val.toJSON() : val);
});
```

#### Получить все фреймы

```javascript
const frames = allObjects.filter(o => o.type === 'frame' && o.labelText);
// → [{ id, labelText, position, width, height, ... }]
```

#### Получить стикеры фрейма

```javascript
const frameId = '{TARGET_FRAME_ID}';
const stickers = allObjects
  .filter(o => o.type === 'sticker' && o.parentId === frameId)
  .map(s => {
    const docVal = s.documentId ? documents.get(s.documentId) : null;
    const text = docVal?.toJSON ? docVal.toJSON() : String(docVal ?? '');
    return {
      id: s.id,
      text,
      fillColor: s.fillColor?.color,
      position: s.position
    };
  });
```

#### Получить тексты (simple-text)

```javascript
const texts = allObjects
  .filter(o => o.type === 'simple-text' && o.parentId === frameId)
  .map(t => {
    const docVal = t.documentId ? documents.get(t.documentId) : null;
    return {
      id: t.id,
      text: docVal?.toJSON ? docVal.toJSON() : String(docVal ?? ''),
      position: t.position
    };
  });
```

## Типы объектов

| type | Описание | Ключевые поля |
|------|----------|---------------|
| `frame` | Фрейм (группировка) | `labelText`, `width`, `height`, `fillColor` |
| `sticker` | Стикер (заметка) | `documentId`, `fillColor`, `textScale` |
| `arrow` | Стрелка/связь | `start.objectId`, `end.objectId`, `arrowType` |
| `simple-text` | Текстовый блок | `documentId` |
| `shape` | Фигура | `shapeType`, `documentId` |

## Формат текста в documents

Тексты могут содержать простую разметку:
- `<bold>текст</bold>` — жирный
- Переносы строк: `\n`
- Большинство текстов — plain text строки

## Пример: полный экспорт фрейма

```javascript
async () => {
  // ... (шаги 2-3: получить doc) ...

  const frameName = 'Чеклист планирования 2026.02.02 Q1 Sprint 2';
  const frame = allObjects.find(o => o.type === 'frame' && o.labelText?.includes(frameName));

  const children = allObjects.filter(o => o.parentId === frame.id);
  const result = {
    frame: frame.labelText,
    stickers: [],
    texts: [],
    arrows: []
  };

  children.forEach(child => {
    const text = child.documentId
      ? (documents.get(child.documentId)?.toJSON?.() ?? String(documents.get(child.documentId) ?? ''))
      : null;

    if (child.type === 'sticker') {
      result.stickers.push({ text, color: child.fillColor?.color });
    } else if (child.type === 'simple-text') {
      result.texts.push({ text });
    } else if (child.type === 'arrow') {
      result.arrows.push({
        from: child.start?.objectId,
        to: child.end?.objectId
      });
    }
  });

  return result;
}
```

## Ограничения

- **Нет публичного API** — всё работает через внутренние сервисы Holst в браузере
- **Требуется авторизация** — MCP-браузер должен быть залогинен
- **Минифицированные имена классов** могут меняться между версиями (поиск сервиса лучше делать по наличию метода `getBackupList$`, а не по имени класса)
- **Бэкапы** обновляются каждые ~10 минут, данные могут быть не самые свежие
- **Yjs V2 формат** — обязательно использовать `applyUpdateV2`, а не `applyUpdate`
