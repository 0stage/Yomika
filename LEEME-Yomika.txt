YOMIKA — LECTOR EPUB CON INICIO DE SESIÓN DE CHATGPT

INICIO
1. Extrae todos los archivos del ZIP en una carpeta.
2. Abre Iniciar-Yomika.bat.
3. Deja abierta la ventana de PowerShell mientras uses Yomika.
4. En el panel de traducción, pulsa «Continuar con ChatGPT» y autoriza el uso del plan.
5. Vuelve a Yomika. La frase o página se traduce dentro del mismo panel.

IMPORTANTE
- Abre Yomika desde Iniciar-Yomika.bat. Abrir el HTML con doble clic no permite completar el inicio de sesión local.
- Se necesita una cuenta y un espacio de trabajo a los que ChatGPT conceda el permiso de uso del plan. El acceso y sus límites los determina OpenAI. No se usa una clave API ni se carga el EPUB a un servidor.
- Al traducir, Yomika envía a OpenAI el texto japonés que hayas seleccionado o la página visible. Las solicitudes usan store:false y streaming.
- Si ya guardaste «Recordar mi autorización», las frases que abras con Shift + clic se traducirán automáticamente. Si acabas de autorizarlo por primera vez, pulsa «Traducir y explicar» una vez; después será automático.
- El identificador de sesión se guarda cifrado con DPAPI para tu usuario de Windows, en %LOCALAPPDATA%\Yomika. El libro sigue guardado solo en tu navegador/dispositivo, como antes.
- El botón «Desconectar» borra la sesión local. Para revocar permisos de la aplicación también puedes revisar la sección de aplicaciones conectadas de tu cuenta ChatGPT.
- Cierra la ventana de PowerShell para detener el servidor local.

ALCANCE
El inicio de sesión de ChatGPT para usar el plan está documentado por OpenAI para aplicaciones de código abierto y alojadas localmente. Para ofrecerlo en una aplicación de pago o alojada remotamente, OpenAI indica que hay que completar su formulario de interés.
