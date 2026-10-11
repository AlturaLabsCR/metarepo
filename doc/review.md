# Revisión de mantenibilidad

## Mejoras aplicadas

- Separar el descubrimiento de paquetes en `lib/mk-packages.nix`. `lib/default.nix`
  concentra la API y el enlace con Nixpkgs; los builders conservan sus módulos.
- Compartir el ámbito base de `callPackage` al descubrir paquetes y publicaciones,
  conservando la inyección selectiva de dependencias de cada función.
- Rechazar canales desconocidos en publicaciones para evitar que un error de
  escritura omita paquetes silenciosamente. Explicar también los formatos inválidos.
- Documentar todas las funciones públicas y los tres helpers internos con
  comentarios `/** … */`, tipos, entradas, valores predeterminados y ejemplos.
- Generar la referencia JSON, Markdown y HTML mediante nixdoc y publicarla junto
  con el repositorio. El constructor vuelve a incluirla al reemplazar `public/`.
- Exponer `formatter` con nixfmt y aplicar un formato uniforme a los archivos Nix.

## Recomendaciones pendientes

1. Añadir pruebas de instalación y actualización en contenedores de las
   distribuciones declaradas cuando se amplíe el catálogo. Las pruebas actuales
   verifican artefactos y hooks, pero no demuestran compatibilidad con cada alias.
2. Probar el flujo de firma completo con una clave efímera: exportación de la
   clave, firmas de paquetes e índices y verificación desde los clientes.
   Resulta especialmente útil antes de depender de firmas en producción.
3. Si aparecen más ejemplos del mismo upstream, compartir sus recetas de
   descarga. Los dos ejemplos Fastfetch repiten un bloque pequeño; extraerlo
   ahora añadiría un módulo y parámetros sin una mejora suficiente.
4. Centralizar metadatos comunes de formatos solamente cuando se añada un formato
   nuevo o haya cambios frecuentes en sus convenciones. La selección actual es
   pequeña y mantener cada builder explícito facilita leer su comportamiento.

La prioridad es reducir duplicación con significado y conservar límites claros.
La documentación y el formato pueden aumentar el número de líneas sin aumentar
la complejidad de la implementación.
