# Generar los entregables visuales

Estos scripts conservan el contenido y la maquetación de las ocho láminas de
Fortop. Generan SVG editables, PNG, PDF individuales, los PDF de negocio y C4,
un PDF conjunto, un índice visual y un ZIP. No usan APIs de IA.

Se necesita Python 3, Cairo y las fuentes DejaVu Sans y DejaVu Sans Mono en
`/usr/share/fonts/truetype/dejavu/`. En Debian o Ubuntu:

```sh
sudo apt-get install python3-venv libcairo2 fonts-dejavu-core
```

Desde la raíz del repositorio:

```sh
python3 -m venv .venv-deliverables
.venv-deliverables/bin/python -m pip install -r tools/deliverables/requirements.txt
.venv-deliverables/bin/python tools/deliverables/fortop_build_core_visuals.py
.venv-deliverables/bin/python tools/deliverables/fortop_build_business.py
.venv-deliverables/bin/python tools/deliverables/fortop_build_c4.py
.venv-deliverables/bin/python tools/deliverables/fortop_package_deliverables.py
```

La salida predeterminada es `fortop-deliverables/`. Para revisar una generación
sin sobrescribir los archivos entregados, define otra carpeta antes de ejecutar
los cuatro scripts:

```sh
export FORTOP_DELIVERABLES_DIR="$(mktemp -d /tmp/fortop-deliverables.XXXXXX)"
```

El generador reutiliza el logotipo original de `fortop_brand_kit/`. El empaquetado
comprueba los SVG, los PNG, el texto de los PDF, las ocho páginas del documento
conjunto y la integridad del ZIP. Ejecútalo después de generar las ocho láminas.
Los contenidos y la fecha de referencia están fijados en los scripts; una nueva
ejecución no actualiza por sí sola el estado del negocio ni de la arquitectura.
