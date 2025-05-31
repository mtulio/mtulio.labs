import google.generativeai as genai
from google.generativeai.types import Tool
import requests
import os
from dotenv import load_dotenv

load_dotenv() # Load environment variables from .env

class AIModelLayer:
    def __init__(self):
        gemini_api_key = os.getenv("GEMINI_API_KEY")
        if not gemini_api_key:
            raise ValueError("GEMINI_API_KEY not found in environment variables. Please set it in .env file.")

        genai.configure(api_key=gemini_api_key)

        # Define the tools (function declarations) that Gemini can call.
        # These correspond to the functions exposed by your MCP server.
        self.available_tools = [
            Tool(
                function_declarations=[
                    {
                        "name": "get_weather",
                        "description": "Get the current weather information for a specific location.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "location": {"type": "string", "description": "The city and state/country, e.g., 'Florianopolis, SC' or 'London, UK'"},
                            },
                            "required": ["location"],
                        },
                    }
                ]
            ),
            Tool(
                function_declarations=[
                    {
                        "name": "generate_random_hello_world",
                        "description": "Generates a random 'hello world' message in different languages or variations.",
                        "parameters": {
                            "type": "object",
                            "properties": {}, # No parameters needed
                        },
                    }
                ]
            )
        ]

        # Initialize the Gemini model with the defined tools
        self.model = genai.GenerativeModel(os.getenv("GEMINI_MODEL"), tools=self.available_tools)
        self.chat_session = self.model.start_chat(history=[])
        print("[AI Model Layer] Gemini model initialized with tools.")

        # Hypothetical MCP Server URL
        self.mcp_server_url = "http://127.0.0.1:5000/mcp/call_tool"

    def _call_mcp_server(self, tool_name: str, tool_args: dict):
        """Internal method to make a request to the MCP server."""
        print(f"[AI Model Layer] Calling MCP Server for tool: {tool_name} with args: {tool_args}")
        try:
            response = requests.post(
                self.mcp_server_url,
                json={"tool_name": tool_name, "tool_args": tool_args}
            )
            response.raise_for_status() # Raise an exception for HTTP errors (4xx or 5xx)
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"[AI Model Layer] Error communicating with MCP server: {e}")
            return {"error": f"Failed to connect to MCP server or tool execution error: {e}"}

    def send_message_to_gemini(self, user_message: str):
        """
        Sends a user message to Gemini, handles tool calls,
        and returns the final Gemini response.
        """
        print(f"[AI Model Layer] User message received: {user_message}")

        # Send the user message to Gemini
        gemini_response = self.chat_session.send_message(user_message)

        # Check if Gemini's response contains a function call (tool request)
        if gemini_response.candidates:
            first_part = gemini_response.candidates[0].content.parts[0]
            if hasattr(first_part, 'function_call') and first_part.function_call:
                function_call = first_part.function_call
                tool_name = function_call.name
                tool_args = {k: v for k, v in function_call.args.items()} # Convert protobuf map to dict

                print(f"[AI Model Layer] Gemini requested tool: {tool_name} with arguments: {tool_args}")

                # Call the MCP server with the identified tool and arguments
                mcp_tool_output = self._call_mcp_server(tool_name, tool_args)

                # Send the tool's output back to Gemini
                print(f"[AI Model Layer] Sending tool output back to Gemini: {mcp_tool_output}")
                try:
                    tool_response_part = genai.protos.Part(
                        function_response=genai.protos.FunctionResponse(
                            name=tool_name,
                            response=mcp_tool_output # Pass the dictionary directly
                        )
                    )
                    final_gemini_response = self.chat_session.send_message(tool_response_part)
                    return final_gemini_response.text
                except Exception as e:
                    print(f"[AI Model Layer] Error sending tool response back to Gemini: {e}")
                    return f"An internal error occurred after calling the tool: {e}"
            else:
                # No function call, just a direct text response from Gemini
                return gemini_response.text
        else:
            return "No response from AI model. Please try again."
