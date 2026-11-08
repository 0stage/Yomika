# Preparar las cuentas online de Yomika

Yomika guarda los EPUB y sus portadas únicamente en IndexedDB del navegador. La cuenta online sincroniza el progreso de lectura y los decks, incluido el vocabulario guardado; el archivo del libro no se sube a Supabase.

## Crear o actualizar el proyecto

1. Crea un proyecto en Supabase.
2. En SQL Editor, abre y ejecuta yomika-supabase-setup.sql. Configura una tabla de progreso por usuario y la tabla de decks; no crea buckets de almacenamiento.
3. En la configuración de API, copia Project URL y la clave Publishable.
4. Configura la dirección HTTPS de Yomika como Site URL y como URL permitida para el enlace de confirmación de correo.

Para conectar el HTML hacen falta únicamente Project URL y la clave Publishable. No uses ni compartas una clave service_role o secret.

## Qué se sincroniza

- En el navegador permanecen el EPUB, su portada y la biblioteca local.
- En Supabase se guardan el progreso (capítulo, posición y modo de lectura) y los decks/palabras.
- Para vincular el progreso a un EPUB sin subir su título ni contenido, Yomika calcula en el navegador una huella SHA-256 del archivo. Esa huella y el progreso se sincronizan; los bytes del EPUB no salen del dispositivo.
- En otro dispositivo, el usuario debe seleccionar su copia local del EPUB para que Yomika encuentre el progreso correspondiente.

## Traducción de páginas y frases

- El botón **Traducir** envía a GPT de OpenAI el texto japonés de la página visible para obtener una traducción natural y fiel al castellano. **Shift + clic** sobre una frase muestra además romaji, vocabulario, verbos y una explicación breve de las estructuras gramaticales.
- La integración usa el modelo GPT-6.1 Terra mediante la API de OpenAI. Hace falta crear una clave en [OpenAI API Platform](https://platform.openai.com/api-keys). La API se factura aparte de la suscripción ChatGPT; algunas cuentas Pro o Business elegibles pueden tener créditos API. Consulta [facturación](https://help.openai.com/en/articles/9039756-managing-billing-for-chatgpt-and-the-api-platform), [créditos para cuentas elegibles](https://help.openai.com/en/articles/20001626-api-credits-benefit-for-eligible-chatgpt-subscriptions) y [precios vigentes](https://developers.openai.com/api/docs/pricing).
- Antes del primer envío, la app pide autorización. Solo envía a OpenAI la frase seleccionada o el texto japonés visible de la página, nunca el archivo EPUB. La solicitud usa `store:false`; OpenAI indica que por defecto no utiliza contenido de la API para entrenar, aunque los registros de seguridad pueden conservarse hasta 30 días. Consulta [controles de datos de la API](https://developers.openai.com/api/docs/guides/your-data).
- La clave se usa desde el navegador y, si eliges recordarla, se guarda localmente en ese navegador; no se envía a Yomika ni se sincroniza con Supabase. No la escribas dentro de un HTML que vayas a compartir o publicar. Para un servicio multiusuario desplegado, la clave debe quedar detrás de un backend seguro.
- El romaji se calcula localmente con el analizador japonés. El audio usa la voz japonesa disponible en el navegador.

## Si ya configuraste una versión anterior

La versión anterior podía crear la tabla kotoba_books y el bucket privado kotoba-epubs. La app nueva deja de subir o descargar archivos EPUB; solo puede leer de la tabla antigua el progreso previo para migrarlo. Si ejecutaste el SQL anterior, los archivos y metadatos existentes no se borran automáticamente y seguirán en tu proyecto Supabase hasta que decidas limpiarlos.