"""Spec for assets/diagrams/A-in-cluster-build.{svg,excalidraw}. Regenerate: python3 -I diagrams/A-in-cluster-build.py

Drawn from the rendered manifests of examples/99-appendix-a-openshift-crc/helm
(helm template, Kubernetes 1.35.6 schemas), not from a run: the BuildConfig and
ImageStream of the Quarkus stack, and the image reference of its Deployment. The
Python stack follows the same path with gql-ch27-python.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=180, h=230, label="Host"),
    dict(x=220, y=50, w=760, h=230, label="Project gql-appendix-a"),
]
nodes = [
    dict(x=35, y=100, w=150, h=140, style="user", lines=["oc start-build", "gql-ch27-quarkus", "--from-dir", "27-final-project/", "quarkus/", "--follow"]),
    dict(x=235, y=100, w=170, h=140, style="accent", lines=["BuildConfig", "gql-ch27-quarkus", "source: Binary", "strategy: Docker", "dockerfilePath:", "Containerfile"]),
    dict(x=430, y=100, w=170, h=140, style="box", lines=["build pod", "runs the", "Containerfile:", "Maven, then the", "runtime image", "ubi10 openjdk-25"]),
    dict(x=625, y=100, w=160, h=140, style="box", lines=["ImageStream", "gql-ch27-quarkus", "tag 1.0", "pushed to the", "internal registry"]),
    dict(x=810, y=100, w=155, h=140, style="sub", lines=["Deployment", "quarkus", "image from the", "internal registry:", "gql-appendix-a/", "gql-ch27-quarkus:1.0"]),
    dict(x=40, y=320, w=920, h=80, style="ghost", lines=["The tag exists before the pods are created", "The release is first installed without the application; the Deployments then read the tag with IfNotPresent", "and start under restricted-v2 with the UID the project assigns."]),
]
edges = [
    dict(x1=185, y1=170, x2=235, y2=170, amber=True, label="tar", lx=0, ly=-12),
    dict(x1=405, y1=170, x2=430, y2=170),
    dict(x1=600, y1=170, x2=625, y2=170, amber=True),
    dict(x1=785, y1=170, x2=810, y2=170, amber=True),
    dict(x1=890, y1=240, x2=890, y2=320, dashed=True),
]
notes = [
    dict(x=500, y=28, text="The image is built where it runs: from the directory of Chapter 27, with its Containerfile, into the project's registry", anchor="middle", bold=True),
    dict(x=500, y=428, text="Values from the rendered manifests; no cluster output is shown in this figure.", anchor="middle", size=12, color="#555555"),
]
g.emit("A-in-cluster-build", 1000, 450, bands=bands, nodes=nodes, edges=edges, notes=notes)
