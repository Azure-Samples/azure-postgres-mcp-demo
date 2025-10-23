# Import necessary libraries

import os, time
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from azure.ai.agents.models import (
    ListSortOrder,
    McpTool,
    RequiredMcpToolCall,
    SubmitToolApprovalAction,
    ToolApproval
)
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()
project_endpoint = os.getenv("PROJECT_ENDPOINT")
model_deployment = os.getenv("MODEL_DEPLOYMENT_NAME")
connection_name = os.getenv("CONNECTION_NAME")

# Get MCP server configuration from environment variables
mcp_server_url = os.environ.get("MCP_SERVER_URL", "https://azure-mcp-postgres-server.graysmoke-6ac73de2.eastus2.azurecontainerapps.io")
mcp_server_label = os.environ.get("MCP_SERVER_LABEL", "postgres")

project_client = AIProjectClient(
    endpoint=os.environ["PROJECT_ENDPOINT"],
    credential=DefaultAzureCredential(),
)
# Initialize agent MCP tool
mcp_tool_config = {
    "type": "mcp",
    "server_url": mcp_server_url,
    "server_label": mcp_server_label,
    "server_authentication": {
        "type": "connection",
        "connection_name": connection_name,
    }
}

mcp_tool_resources = {
    "mcp": [
        {
            "server_label": mcp_server_label,
            "require_approval": "never"
        }
    ]
}

# Create agent with MCP tool and process agent run
with project_client:
    agents_client = project_client.agents

    # Create a new agent.
    # NOTE: To reuse existing agent, fetch it with get_agent(agent_id)
    agent = agents_client.create_agent(
        model=os.environ["MODEL_DEPLOYMENT_NAME"],
        name="ignite-demo-agent-mcp",
        #"command":"postgres_database_query"
        instructions="""
        You are a helpful agent that can use MCP tools to assist users. Use the available MCP tools to answer questions and perform tasks.
        {
        "database": "nlweb_db_2",
        "resource-group": "abeomor",
        "server": "diskannga",
        "subscription": "5c5037e5-d3f1-4e7b-b3a9-f6bf94902b30",
        "user": "azure-mcp-postgres-server",
        learn: true
        }
        """,
        tools=[mcp_tool_config],
    )

    print(f"Created agent, ID: {agent.id}")
    print(f"MCP Server: {mcp_server_label} at {mcp_server_url}")

    # Create thread for communication
    thread = agents_client.threads.create()
    print(f"Created thread, ID: {thread.id}")

    input_text = [
    """
    Can you list all the tables in the database?
    """,
    """
    Can you find info about AI in my database? From the documents table. I want to see the id and name.
    """,
    """
    What tools are available, list them? Can you run a query on the Postgres database?
    """,
    """
    Do a vector search for "Talks about AI" on my postgres database

    this is a vector search example.
    SELECT id, name, embedding <=> azure_openai.create_embeddings(
    'text-embedding-3-small',
    'query example'
    )::vector AS similarity
    FROM public.products
    ORDER BY similarity
    LIMIT 10;
    """
    ]


    # Create message to thread
    message = agents_client.messages.create(
        thread_id=thread.id,
        role="user",
        content=input_text[1]
        #content="Can you find info about AI in my database? From the documents table" #--- Broken
    )
    print(f"Created message, ID: {message.id}")
    # Create and process agent run in thread with MCP tools
    # mcp_tool.update_headers("SuperSecret", "123456")
    # mcp_tool.set_approval_mode("never")  # Uncomment to disable approval requirement
    run = agents_client.runs.create(thread_id=thread.id, agent_id=agent.id, tool_resources=mcp_tool_resources)
    print(f"Created run, ID: {run.id}")

    while run.status in ["queued", "in_progress", "requires_action"]:
        time.sleep(1)
        run = agents_client.runs.get(thread_id=thread.id, run_id=run.id)

        if run.status == "requires_action" and isinstance(run.required_action, SubmitToolApprovalAction):
            tool_calls = run.required_action.submit_tool_approval.tool_calls
            if not tool_calls:
                print("No tool calls provided - cancelling run")
                agents_client.runs.cancel(thread_id=thread.id, run_id=run.id)
                break

            tool_approvals = []
            for tool_call in tool_calls:
                if isinstance(tool_call, RequiredMcpToolCall):
                    try:
                        print(f"Approving tool call: {tool_call}")
                        tool_approvals.append(
                            ToolApproval(
                                tool_call_id=tool_call.id,
                                approve=True
                            )
                        )
                    except Exception as e:
                        print(f"Error approving tool_call {tool_call.id}: {e}")

            print(f"tool_approvals: {tool_approvals}")
            if tool_approvals:
                agents_client.runs.submit_tool_outputs(
                    thread_id=thread.id, run_id=run.id, tool_approvals=tool_approvals
                )

        print(f"Current run status: {run.status}")

    print(f"Run completed with status: {run.status}")
    if run.status == "failed":
        print(f"Run failed: {run.last_error}")

    # Display run steps and tool calls
    run_steps = agents_client.run_steps.list(thread_id=thread.id, run_id=run.id)

    # Loop through each step
    for step in run_steps:
        print(f"Step {step['id']} status: {step['status']}")

        # Check if there are tool calls in the step details
        step_details = step.get("step_details", {})
        tool_calls = step_details.get("tool_calls", [])

        if tool_calls:
            print("  MCP Tool calls:")
            for call in tool_calls:
                print(f"    Tool Call ID: {call.get('id')}")
                print(f"    Type: {call.get('type')}")

        if hasattr(step_details, 'activities'):
            for activity in step_details.activities:
                for function_name, function_definition in activity.tools.items():
                    print(
                        f'  The function {function_name} with description "{function_definition.description}" will be called.:'
                    )
                    if len(function_definition.parameters) > 0:
                        print("  Function parameters:")
                        for argument, func_argument in function_definition.parameters.properties.items():
                            print(f"      {argument}")
                            print(f"      Type: {func_argument.type}")
                            print(f"      Description: {func_argument.description}")
                    else:
                        print("This function has no parameters")

        print()  # add an extra newline between steps

    # Fetch and log all messages
    messages = agents_client.messages.list(thread_id=thread.id, order=ListSortOrder.ASCENDING)
    print("\nConversation:")
    print("-" * 50)
    for msg in messages:
        if msg.text_messages:
            last_text = msg.text_messages[-1]
            print(f"{msg.role.upper()}: {last_text.text.value}")
            print("-" * 50)


    # Clean-up and delete the agent once the run is finished.
    # NOTE: Comment out this line if you plan to reuse the agent later.
    # agents_client.delete_agent(agent.id)
    # print("Deleted agent")