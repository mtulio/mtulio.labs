from fastmcp import FastMCP

# Initialize your MCP server with a descriptive name
mcp = FastMCP("MyLocalCalculator")

@mcp.tool()
def add(a: float, b: float) -> float:
    """Adds two numbers together."""
    return a + b

@mcp.tool()
def subtract(a: float, b: float) -> float:
    """Subtracts the second number from the first."""
    return a - b

@mcp.tool()
def multiply(a: float, b: float) -> float:
    """Multiplies two numbers."""
    return a * b

@mcp.tool()
def divide(a: float, b: float) -> float:
    """Divides the first number by the second. Handles division by zero."""
    if b == 0:
        raise ValueError("Cannot divide by zero.")
    return a / b

# You can also define resources (for static data) and prompts (reusable templates)
@mcp.resource("info://about")
def get_info() -> str:
    """Provides information about this server."""
    return "This is a simple local calculator server powered by FastMCP."

# This block ensures the server runs when the script is executed directly
if __name__ == "__main__":
    print("Starting MyLocalCalculator MCP server...")
    mcp.run()
