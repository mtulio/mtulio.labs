import streamlit as st
from ai_model_layer import AIModelLayer # Import your AI model layer

st.set_page_config(page_title="Gemini MCP Chatbot")

# Initialize AIModelLayer (this will load API key and set up Gemini)
# Use st.cache_resource to avoid re-initializing on every rerun
@st.cache_resource
def get_ai_model_layer():
    try:
        return AIModelLayer()
    except ValueError as e:
        st.error(f"Configuration Error: {e}. Please ensure your GEMINI_API_KEY is set in the .env file.")
        st.stop() # Stop the app if API key is missing

ai_model_layer = get_ai_model_layer()

st.title("🤖 Gemini MCP Chatbot")

# Initialize chat history in session state
if "messages" not in st.session_state:
    st.session_state.messages = []

# Display chat messages from history
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

# User input
if prompt := st.chat_input("Ask me anything... (e.g., 'What's the weather in London?', 'Say hello.')"):
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    with st.chat_message("assistant"):
        with st.spinner("Thinking..."):
            # Send message to your AI model layer
            ai_response = ai_model_layer.send_message_to_gemini(prompt)
            st.markdown(ai_response)
    st.session_state.messages.append({"role": "assistant", "content": ai_response})
