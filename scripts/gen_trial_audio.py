# -*- coding: utf-8 -*-
"""生成睡背APP试听音频：轮询式重试，错开请求时间对抗限流"""
import asyncio
import os
import edge_tts

OUT_DIR = r"E:\WorkSpace\SleepAPP\试听音频"
os.makedirs(OUT_DIR, exist_ok=True)

TEXT = (
    "盼望着，盼望着，东风来了，春天的脚步近了。"
    "一切都像刚睡醒的样子，欣欣然张开了眼。"
    "山朗润起来了，水涨起来了，太阳的脸红起来了。"
    "小草偷偷地从土里钻出来，嫩嫩的，绿绿的。"
)

VOICES = [
    ("晓晓·默认温柔女声", "zh-CN-XiaoxiaoNeural"),
    ("晓梦·轻柔女声", "zh-CN-XiaomengNeural"),
    ("晓双·温柔女声", "zh-CN-XiaoshuangNeural"),
    ("晓悠·柔和女声", "zh-CN-XiaoyouNeural"),
    ("晓伊·明亮女声", "zh-CN-XiaoyiNeural"),
    ("云希·男声对照", "zh-CN-YunxiNeural"),
]

MAX_CYCLES = 12
SLEEP_BETWEEN = 20  # 每个周期之间休息，错开限流


async def gen(name: str, voice: str) -> bool:
    path = os.path.join(OUT_DIR, f"{name}.mp3")
    try:
        tts = edge_tts.Communicate(TEXT, voice, rate="-10%")
        await tts.save(path)
        size = os.path.getsize(path)
        print(f"OK   {name}  ({voice})  {size} bytes", flush=True)
        return True
    except Exception as e:
        print(f"FAIL {name} attempt: {type(e).__name__}", flush=True)
        return False


async def main() -> None:
    pending = {name: voice for name, voice in VOICES}
    for cycle in range(1, MAX_CYCLES + 1):
        if not pending:
            break
        print(f"--- cycle {cycle}: {len(pending)} pending ---", flush=True)
        for name, voice in list(pending.items()):
            if await gen(name, voice):
                del pending[name]
            await asyncio.sleep(5)  # 同周期内错开
        if pending:
            print(f"sleep {SLEEP_BETWEEN}s before next cycle", flush=True)
            await asyncio.sleep(SLEEP_BETWEEN)
    if pending:
        print("STILL FAILED: " + ", ".join(pending.keys()), flush=True)
    else:
        print("ALL DONE", flush=True)


if __name__ == "__main__":
    asyncio.run(main())
