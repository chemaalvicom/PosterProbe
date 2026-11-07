# PosterProbe

App de diagnóstico para iOS 17+ que intenta leer los **Pósters de Contacto** de la agenda
mediante claves internas de `CNContact` (no hay API pública) y vuelca lo que consiga en
*Archivos › En mi iPhone › PosterProbe*. No envía nada fuera del iPhone.

- Compilación sin firmar en GitHub Actions (XcodeGen). La IPA se publica en la release `latest`.
- Firmar e instalar con ESign. No apta para App Store (usa API privada).

Salida por ejecución: `informe.txt` (claves accesibles, clases del runtime),
`resumen.csv`, y `contactos/<Nombre>__<id>/` con los blobs del póster y `meta.json`.
