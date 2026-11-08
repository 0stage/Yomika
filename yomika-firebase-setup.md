# Preparar las cuentas online de Yomika (Firebase)

Yomika guarda los EPUB y sus portadas únicamente en IndexedDB del navegador. La cuenta online sincroniza el progreso de lectura y los decks, incluido el vocabulario guardado; el archivo del libro no se sube a ningún servidor.

## Crear el proyecto

1. En la [consola de Firebase](https://console.firebase.google.com/) crea un proyecto. El plan gratuito (Spark) basta y no pide tarjeta.
2. En **Authentication → Sign-in method** activa **Correo electrónico/contraseña**.
3. En **Firestore Database** crea una base de datos en modo producción y elige una región cercana.
4. En **Firestore → Reglas**, pega el contenido de [firestore.rules](firestore.rules) y publícalas. Sin estas reglas, nadie podría leer ni escribir.
5. En **Configuración del proyecto → Tus apps**, registra una app web y copia su configuración (`apiKey`, `authDomain`, `projectId`, `appId`) en la constante `FIREBASE_CONFIG` al principio del script de `index.html`. Esos valores son públicos por diseño; la seguridad la dan las reglas del paso 4.
6. En **Authentication → Configuración → Dominios autorizados**, añade el dominio donde alojes Yomika (por ejemplo, tu dominio de Cloudflare Pages).

Para plantillas de correo (confirmación y restablecer contraseña) usa **Authentication → Plantillas**. Los correos de Firebase salen de su propio remitente; si los quieres con tu dominio, configura un remitente personalizado allí.

## Cómo funcionan las cuentas

- Al crear una cuenta, Firebase envía un correo de confirmación. Hasta que se confirma no se puede entrar, y las reglas también lo exigen (`email_verified`).
- La pantalla de inicio de sesión incluye «¿Olvidaste tu contraseña?», que envía el enlace de restablecimiento.
- Si quieres cerrar el registro público una vez creadas las cuentas necesarias, desactiva el proveedor o usa la opción de bloquear altas en Authentication → Configuración.

## Qué se sincroniza

- En el navegador permanecen el EPUB, su portada y la biblioteca local.
- En Firestore se guardan el progreso (capítulo, posición y modo de lectura) y los decks/palabras.
- Para vincular el progreso a un EPUB sin subir su título ni contenido, Yomika calcula en el navegador una huella SHA-256 del archivo. Esa huella y el progreso se sincronizan; los bytes del EPUB no salen del dispositivo.
- En otro dispositivo, el usuario debe seleccionar su copia local del EPUB para que Yomika encuentre el progreso correspondiente.

## Estructura de datos

```
users/{uid}/progress/{huella-del-libro}   { progress: {ch, fr, v, u}, updatedAt }
users/{uid}/decks/{deckId}                { name, created, updatedAt, chunkCount, wordCount, hashes }
users/{uid}/decks/{deckId}/chunks/{n}     { words: [...] }   (hasta 400 palabras por documento)
```

Las palabras se guardan en trozos porque un documento de Firestore no puede superar 1 MiB. Solo se reescriben los trozos que cambian.

## Costes

Con el plan gratuito de Firebase no hay facturación: si se supera una cuota diaria, la función se detiene hasta el día siguiente. Para dos o tres usuarios las cuotas sobran. Consulta los [precios vigentes](https://firebase.google.com/pricing).

## Traducción con IA

La traducción con IA está desactivada por ahora (`AI_TRANSLATION_ENABLED=false` en `index.html`). El romaji, el diccionario y los decks funcionan igual. Cuando se conecte un servicio de traducción, su clave debe guardarse en un backend (por ejemplo, un Worker de Cloudflare) y no en la página.

## Datos de una versión anterior con Supabase

Esta versión ya no usa Supabase y no migra automáticamente los datos que hubiera allí. Los libros, el progreso y los decks guardados en el navegador (modo invitado) se importan a la cuenta nueva la primera vez que se inicia sesión.
