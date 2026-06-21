"""Smoke-test component: a real cofiswarm-observer-sdk Python ServiceComponent that announces
presence on the NATS observer bus and, on SIGTERM/SIGINT, says goodbye. Used by
observer-presence-smoke.sh to exercise the full Python attach path end-to-end.
"""
import asyncio
import os
import signal

from cofiswarm_observer import ServiceComponent

COMPONENT_ID = os.environ.get("SMOKE_COMPONENT", "smoke-py")
NATS_URL = os.environ.get("COFISWARM_NATS_URL", "nats://127.0.0.1:4222")


async def main() -> None:
    nc = await ServiceComponent.connect(NATS_URL, COMPONENT_ID)

    async def info(_req: dict) -> dict:
        return {"engine": "smoke"}

    comp = ServiceComponent(
        nc, COMPONENT_ID, COMPONENT_ID,
        {f"swarm.observer.infer.{COMPONENT_ID}.info": info},
    )
    await comp.start()
    print(f"announced {COMPONENT_ID} on {NATS_URL}", flush=True)

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    await stop.wait()

    await comp.shutdown()  # goodbye -> offline
    await nc.close()
    print(f"goodbye {COMPONENT_ID}", flush=True)


if __name__ == "__main__":
    asyncio.run(main())
