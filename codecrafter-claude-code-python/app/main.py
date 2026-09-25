import argparse
import os
import sys
import json
from typing import Any, cast
from openai import OpenAI
from .utils import bash, get_tools, read_file, write_file

API_KEY = os.getenv("OPENROUTER_API_KEY")
BASE_URL = os.getenv("OPENROUTER_BASE_URL", default="https://openrouter.ai/api/v1")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("-p", required=True)
    args = p.parse_args()

    if not API_KEY:
        raise RuntimeError("OPENROUTER_API_KEY is not set")

    client = OpenAI(api_key=API_KEY, base_url=BASE_URL)
    tools = get_tools()
    messages: list[Any] = [{"role": "user", "content": args.p}]

    model = "anthropic/claude-haiku-4.5"

    while True:
        chat = client.chat.completions.create(
            model=model, messages=messages, max_tokens=1000, tools=tools
        )

        if not chat.choices or len(chat.choices) == 0:
            raise RuntimeError("no choices in response")

        message = chat.choices[0].message

        messages.append(
            {"role": "assistant", "content": None, "tool_calls": message.tool_calls}
        )

        if not message.tool_calls:
            print(message.content)
            break

        tool_map = {"Read": read_file, "Write": write_file, "Bash": bash}
        for tool_call in message.tool_calls:
            tool = tool_map[tool_call.function.name]
            tool_args = tool_call.function.arguments
            args = json.loads(tool_args)
            result = tool(**args)
            messages.append(
                {"role": "tool", "tool_call_id": tool_call.id, "content": result}
            )


if __name__ == "__main__":
    main()