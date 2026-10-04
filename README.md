# Camp Bach · Andrea

Página para el fin de semana en Valle de Bravo, del 8 al 11 de octubre de 2026.

- `index.html`: página completa con imágenes, estilos y JavaScript integrados. Lista para servir desde la raíz en GitHub Pages o Netlify.
- `camp-bach-andrea.zip`: código fuente separado en HTML, CSS, JavaScript, imágenes y configuración, con instrucciones de instalación.

Incluye paisaje ilustrado, parallax, parches bordados interactivos, contador, itinerario, mapas y juegos.

## Juegos

Yo nunca nunca funciona desde una pantalla. La trivia ya tiene configurada la conexión pública a Supabase. Para activarla, habilita **Anonymous Sign-Ins** en Authentication y ejecuta `activar-juego-camp-bach.sql` en el SQL Editor del proyecto Camp Bach. Las invitadas entran sin correo ni contraseña; el código permite unirse a una sala y sus datos solo son visibles a sus integrantes.

La anfitriona crea una sala; las demás entran con su código desde otro celular. Cada una completa su perfil y la anfitriona inicia la partida cuando haya al menos dos listas.

## Publicación

En GitHub Pages selecciona la rama `main` y la carpeta raíz `/`. En Netlify, publica la raíz sin comando de build.
