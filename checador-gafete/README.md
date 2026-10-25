# Checador con gafete obligatorio

Sistema de reloj checador (clock-in) para tienda/restaurante que **no deja checar la entrada si no traes tu gafete**.

## Cómo funciona

1. **Escanea el gafete.** Cada gafete lleva una calcomanía con un código QR único. El empleado lo acerca a la cámara de la tablet (o a un lector USB). Sin gafete, no avanza.
2. **PIN personal.** Después de escanear, pone su PIN. Así nadie puede checar con el gafete de otro.
3. **Foto con el gafete puesto.** La tablet toma una foto (cuenta regresiva de 3 s) como prueba de que el gafete está en el uniforme. Se puede apagar en *Ajustes*.
4. **Entrada / Inicio descanso / Fin descanso / Salida.** Solo se habilitan los botones que tienen sentido (ej. no puedes marcar salida si no marcaste entrada).

### ¿Y si no trae el gafete?
Botón **"No traigo mi gafete"** → solo un **gerente con su PIN** puede autorizarlo, eligiendo el motivo (olvidado, perdido, dañado, empleado nuevo). Queda registrado como **incidente** y aparece en el reporte con contador por empleado.

## Panel de gerente
- **Empleados:** agregar, cambiar PIN, activar/desactivar, **imprimir QR** para pegar en el gafete, y **"Gafete nuevo"** (invalida el código anterior si se pierde).
- **Registros:** checadas por día con foto, exportar a CSV (Excel).
- **Incidentes sin gafete:** quién, cuándo, por qué y quién autorizó.
- **Ajustes:** nombre de la tienda, foto obligatoria, PIN del gerente, días que se guardan las fotos.

La primera vez que entras a *Gerente* te pide crear el PIN.

## Instalación (tablet como kiosco)
No necesita instalar nada ni internet: son archivos HTML/JS.

```bash
cd checador-gafete
python3 -m http.server 8080
# abrir http://localhost:8080 en la tablet/PC
```

> La cámara solo funciona en `https://` o `localhost`. Para usarlo desde otra tablet en la red, publícalo con HTTPS (por ejemplo GitHub Pages).

**Imprimir gafetes:** Gerente → Empleados → *Imprimir QR*. Imprime en papel de etiqueta y pega el QR atrás o abajo del gafete.

## Limitaciones
- Los datos se guardan en el navegador de **esa** tablet (`localStorage`). Si se borran los datos del navegador, se pierden: exporta el CSV seguido. Para varias tiendas o integración con nómina haría falta un servidor.
- Las fotos se guardan pequeñas (320 px) y se borran solas después de los días configurados.

Librerías incluidas en `vendor/`: [jsQR](https://github.com/cozmo/jsQR) (Apache-2.0) y [qrcodejs](https://github.com/davidshimjs/qrcodejs) (MIT).
