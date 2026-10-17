"""Resolver layer, pure units: DeliveryDerivation calls no source, so it runs with no server."""
from datetime import UTC, datetime

from app import data
from app.derivation import DeliveryDerivation
from app.handling import HandlingRecord
from app.model import HandlingEventType, TransportStatus

derivation = DeliveryDerivation(data.LOCATIONS, data.VOYAGES)


def test_an_unload_at_a_port_leaves_the_cargo_in_port() -> None:
    unload = HandlingRecord(
        id="evt_t1",
        tracking_id="ABC123",
        type=HandlingEventType.UNLOAD,
        un_locode="DEHAM",
        voyage_number="V100S",
        completion_time=datetime(2026, 10, 9, 15, 0, tzinfo=UTC),
        registration_time=datetime(2026, 10, 9, 15, 1, tzinfo=UTC),
    )

    delivery = derivation.derive(data.CARGOS["ABC123"], data.ITINERARIES["ABC123"], [unload])

    assert delivery.transport_status is TransportStatus.IN_PORT
    assert delivery.current_voyage is None
    assert delivery.last_known_location.un_locode == "DEHAM"


def test_a_cargo_with_no_events_is_not_received() -> None:
    delivery = derivation.derive(data.CARGOS["ABC123"], data.ITINERARIES["ABC123"], [])

    assert delivery.transport_status is TransportStatus.NOT_RECEIVED
    assert delivery.last_known_location is None
