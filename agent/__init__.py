"""MCP Server for Azure resource deployment with compliance orchestration."""

__version__ = "1.0.0"
__author__ = "Siddhant Jha"

from agent.server import mcp, main

__all__ = ["mcp", "main", "__version__"]
