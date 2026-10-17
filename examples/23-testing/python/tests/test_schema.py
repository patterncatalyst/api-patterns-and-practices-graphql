"""Schema layer: the SDL Strawberry builds from the decorated classes."""
import os
from pathlib import Path

from app.schema import schema


def test_exported_schema_declares_the_contract_types_and_scalars() -> None:
    sdl = schema.as_str()

    assert "type Cargo implements Node" in sdl
    assert "scalar TrackingId" in sdl
    assert "input RegisterHandlingEventInput" in sdl

    export_dir = Path(os.environ.get("TRACKING_TEST_EXPORT_DIR", "build"))
    export_dir.mkdir(parents=True, exist_ok=True)
    (export_dir / "schema.graphql").write_text(sdl)
