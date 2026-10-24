#!/usr/bin/env bash
set -euo pipefail

/usr/bin/python3.11 - <<'PY'
import fcntl
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

TARGET = Path("/projects/python-packages")
MARKER = TARGET / "setup-completo.json"

REDHAT_INDEX = (
    "https://packages.redhat.com/api/pypi/"
    "public-rhai/rhoai/3.5/cpu-ubi9/simple/"
)
PYPI_INDEX = "https://pypi.org/simple"

CONFIG = {
    "setup_version": 1,
    "python": list(sys.version_info[:2]),
    "kubeflow": "0.3.0+rhaiv.3",
    "pyspark": "4.0.1",
    "pyarrow": "24.0.0",
}

VALIDATE = """
from kubeflow.spark import SparkClient
from kubeflow.common.types import KubernetesBackendConfig
from kubeflow.spark.types.types import Driver
import pyspark
import pyarrow
import pandas
import grpc
import zstandard
import ipykernel
import matplotlib

assert pyspark.__version__ == "4.0.1"
assert pyarrow.__version__ == "24.0.0"
print("Dependencias Spark validadas.")
"""


def run(*args, env=None):
    subprocess.run(
        [str(arg) for arg in args],
        check=True,
        env=env,
    )


# Não usar pacotes de uma instalação incompleta durante o pip.
install_env = os.environ.copy()
install_env.pop("PYTHONPATH", None)

runtime_env = os.environ.copy()
runtime_env["PYTHONPATH"] = str(TARGET)

Path("/projects").mkdir(parents=True, exist_ok=True)

with open("/projects/.spark-python-setup.lock", "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)

    if MARKER.exists():
        saved = json.loads(MARKER.read_text())

        if saved != CONFIG:
            raise RuntimeError(
                "A configuracao Python mudou. "
                "O administrador deve preparar outra versao do ambiente."
            )

        run(sys.executable, "-c", VALIDATE, env=runtime_env)
        print("Ambiente reutilizado. Nenhum pip install executado.")

    else:
        TARGET.mkdir(parents=True, exist_ok=True)

        print("Primeira inicializacao: preparando bibliotecas...")

        with tempfile.TemporaryDirectory(
            prefix="spark-wheels-",
            dir="/projects",
        ) as temp_dir:
            temp = Path(temp_dir)

            # Obtém especificamente o wheel upstream do PyArrow.
            run(
                sys.executable, "-m", "pip", "download",
                "--index-url", PYPI_INDEX,
                "--only-binary=:all:",
                "--no-deps",
                "--dest", temp,
                "pyarrow==24.0.0",
                env=install_env,
            )

            arrow_wheel = next(temp.glob("pyarrow-*.whl"))

            # O wheel explícito evita selecionar outro build do PyArrow.
            run(
                sys.executable, "-m", "pip", "install",
                "--target", TARGET,
                "--upgrade",
                "--index-url", REDHAT_INDEX,
                "--extra-index-url", PYPI_INDEX,
                arrow_wheel,
                "kubeflow[spark]==0.3.0+rhaiv.3",
                "pyspark-connect==4.0.1",
                "zstandard",
                "ipykernel",
                "matplotlib",
                env=install_env,
            )

        run(sys.executable, "-c", VALIDATE, env=runtime_env)

        temporary_marker = MARKER.with_suffix(".tmp")
        temporary_marker.write_text(json.dumps(CONFIG, indent=2))
        temporary_marker.replace(MARKER)

        print("Preparacao concluida e registrada no PVC.")
PY