# Lab notes | AWS Gen AI solutions

## Terms and technologies

AWS Sagemaker

AWS Sagemaker JumpStart

Sagemaker endpoints

LangChain: is an open source framework for building applications based on LLMs


FAISS - Facebook AI Similarity Search: for efficient similarity searches and embeddings to represent documents in a searchable space.

Jupyter notebooks

Semantic search

Promp engineering

Amazon SageMaker Studio Lab provides pre-installed environments for your Studio Lab notebook instances. Using environments, you can start up a Studio Lab notebook instance with the packages you want to use. This is done by installing packages in the environment and then selecting the environment as a Kernel.

LangChain is an open source framework for building applications based on large language models (LLMs). LLMs are large deep-learning models pre-trained on large amounts of data that can generate responses to user queries - for example, answering questions or creating images from text-based prompts.

LangChain: streamlines intermediate steps to develop such data-responsive applications, making prompt engineering more efficitnet, it is designed to develop diverse applications powered by language models more effortlessly, including chatbots, quetion-answering, content generation,summarizes, and more.

Prompt Template: consists of a string template. It accepts a set of parameters from the user that can be used to generate prompt for a language model.

Chains: are the fundamental principle that holds various AI components in LangChain to provide context-ware responses

Retrieval Augmented Generation (RAG): is the process of optimizing the output of an LLB, so the LLM references an authoritative knowledge base outside of its training data sources before generating a response.

Text embedding: refers to the process of transforming text into numerical representations that resides in a high dimensional vector space.

Faiss (Facebook AI Similarity Search) is a library for efficient similarity search and clustering of dense vectors. It contains algorithms that search in sets of vectors of any size, up to ones that possibly do not fit in RAM. It also contains supporting code for evaluation and parameter tuning.

SPA: single-page application

## Practive Labs

- How to import a model from community and serve it

- How to re-train a model and serve it


- Depploy a foundation model through SageMaker JumpStart


### Practice: LangChain


hf-textembedding-gpt-j-6b-fp16
hf-llm-falcon-7b-instruct-bf16

aws s3 synch s3://lab-code-0ee8a540/ .


### Practice: Promp Engineering with Amazon Bedrock

Learning Prompt Engineering techniques to improve the responses.

What is Prompt Engineering?
Prompt Engineering is the process of designing the right prompt to get the desired output from a large language model (LLM). This involves crafting the right question or statement to guide the LLM towards providing the desired output. Prompt Engineering is important because LLMs are trained on large amounts of data and can generate responses that are not always accurate or relevant. By carefully designing the prompt, it is possible to improve the quality of the output and make the LLM more useful for a specific task. Prompt Engineering is an emerging field and is still being explored and developed by researchers and practitioners. As LLMs continue to evolve and become more sophisticated, the field of Prompt Engineering is likely to become even more important.

What is Amazon Bedrock?
Amazon Bedrock is a service that allows developers to easily access foundation models (FMs) from leading AI startups and Amazon to build applications with natural language capabilities. The service offers a selection of large language models (LLMs) from AI21 Labs, Anthropic, Stability AI, and Amazon, including Jurassic-2, Claude, Stable Diffusion, Titan, and Amazon Titan. With Amazon Bedrock, developers can access foundation models through an API, customize them with their own data, and integrate them into their applications with just a few lines of code. Amazon manages the infrastructure, model updates, and pricing for the service, making it easy for developers to get started with LLMs. By using Amazon Bedrock, developers can build applications with natural language capabilities, such as chatbots, virtual assistants, and language translation tools.

Hands on:

LAB_BUCKET=$(aws s3 ls | grep lab-resources | awk '{print$3}')
aws s3 sync s3://$LAB_BUCKET/ .

zip lambda_function.zip lambda_function.py
aws lambda update-function-code --function-name invoke_bedrock --zip-file fileb://lambda_function.zip

WEB_BUCKET=$(aws s3 ls | grep www- | awk '{print$3}')


Concepts:

Prompt engineering refers to the practice of optimizing textual inputs to LLMs to obtain desired responses. Prompting helps LLMs perform a wide variety of tasks, including classification, question answering, code generation, creative writing, and more

Prompts are a specific set of inputs provided by you, the user, that guide LLms on Amazon Bedrock to generate an appropriate response or output for a given task or instruction

A single promp includes several components, such as the task or instruction that you want the LLms to perform, the context of the task (for example, a description of the relevant domain), demonstration examples, and the input text that you want LLms on Amazon Bedrock to use in its repsonse.

Depending on your use casem the availability of the data, and the task, you prompt should combine one or more of these components.

2. Estimate audience for TV shows based on historical data.
Chain-of-thought promptingt is a technique that breaks down a complex question into smaller, logical parts that mimic a train of thought. This helps the model to solve problems in a series of intermediate steps rather than directly answering the question. This enhances is reasoning ability.

3; Creating question-answering assistant.

To help LLms better calibrate their output to meet your expectations, you can provide a few examples, also known as few-shot prompting or in-context learning, where a shot corresponds to a paired example input and the desired output.

Few-shot prompting means that you give the LLM a few shots to learn what you want by providing it with some examples.


4. Create splash pages that describe upcoming events

Unlike few-shot prompting, which guides the model with specific examples, zero-shot prompting relies solely on a clear instruction and the model's pre-existing knowledge.

A broader application is possible with zero-shot prompting, without needing task-specific training data. However, zero-shot results can be less accurate, specially for complex tasks.



### Practice: Build an Deploy Tools Using LLM Agents

- Agents for Amazon Bedrock (service feature)
- Action group: defines actions that the agent can help end users perform. Each action group includes the parameter that the agent must elicit from the end user.

- OAS - Open API Specification

Steps/Concepts:

Enable Titan model on Bedrock

Amazon Titan models are created by AWS and pre-trained on large datasets, making them powerful, general-purpose models built to support a variety of use cases, while also supporting the responability use of AI

Agents for Amazon Bedrock provides fully managed capabilities that help developers create generative artificial inteligence (AI)-based applications that can complete complex tasks for a wide range of use cases and deliver up-to-date answers based on proprietary knowledge sources.

With agents, you can automate tasks for your customers and answer questions for them. For example, you can create an agent that helps customers process insurance claims or an agent that helps customers make travel reservations.

You choose a foundation mode (FM) that the agent invokes to interpret user input and subsequent prompts in its orchestration process. The agent also invokes the FM to generate responses and follow-up steps in its process.

You write instructions that describe what the agent is designed to do. With advanced prompts, you can further customize instructions for the agent at every step of orchestration and include lambda functions to parse each step's output.

Action group for an agent:

An action group defines actions that the agent can help the user perform. For example, you could define an action group called BookHotel that helps users carry out actions that you can define such as:
- CreateBooking - Helps users book a hotel
- GetBooking - Helps users get information about a hotel they booked
- CancelBooking - Help users cancel a booking

When you create an action group in Amazon Bedrock, you must define the parameters that the agent needs to invoke from the user. You can also define API operations that the agent can invoke using these parameters.

The agent uses the schema to determine the API operation that it needs to invoke and the parameter that are required to make the API request. These details are then sent through a Lambda function that you define to carry out the action or returned in the response of the agent invocation.

Test Agent traces gives you the visibility into the agent's reasoning, known as the Chain of Thought (CoT).

To deploy an Agent, you must create an alias. During alias creation, Amazon Bedrock creates a version of your agent automatically.

### Practice: Build Generative AI Apps with Foundation Models

Concetps:

- Creating RAG from internal documents (Q&A)
- SageMaker Endpoint

> "Quick introduction to LangChain and why it it useful for RAG-based applications.
LangChain is a framework for developing applications powered by language models.

> LLMs are powerful by themselves. Why are libraries like LangChain needed?
> While LLMs are powerful, they are also general in nature (and therefore, in some cases, kind of boring and limited). While LLMs can perform many tasks effectively, they are not able to provide specific answers to questions or tasks that require deep, domain-specific knowledge or expertise. For example, imagine that an LLM is used to answer questions about a specific field, such medicine or law. While the LLM might be able to answer general questions about the field, it might not be able to provide more detailed or nuanced answers that require specialized knowledge or expertise. To work around this limitation, LangChain offers a useful approach. In LangChain, the corpus of text is preprocessed by breaking it down into chunks or summaries, embedding them in a vector space, and searching for similar chunks when a question is asked. LangChain also provides a level of abstraction, making it user-friendly.

> How is this need for specific knowledge resolved?
> Retrieval Augmented Generation (RAG) is a design pattern that enterprise customers can use to securely bring domain context and their artifacts while using LLMs to answer questions."**


Very cool lab using streamlit, using FM to LLM and RAG processed data with custom FAQ.


```sh
aws s3 cp s3://lab-code-d7cf8010/application-files.zip 
unzip application-files.zip
pip install -r requirements.txt 
streamlit run main.py
```


### Practice: Code generation with prompt engineering

Comments:

- Bedrock is similar ollama (?)


See:

```
# gen-ai/code-generation-prompt
$ ls
bedrock_function.py  index.html  template.py  user_prompts.txt
```


### Practice: Generate an AWS Q&A Application


Goal:
- Create Q&A application
- Frontend chat is served by static HTML, querying API using API GW
- API GW have lambda proxy integration to handle the message, sending to bedrock
- Bedrock have different FAQs templates in Python to answer custom information


Steps:
- Enable model: Amazon Titan Text G1 - Premier
- Review lambda function
- Check lambda env config pointing to the correct FAQ
- Open the CloudFront URL 
- Copy the API GW URL for the frontned for the `generate`path
- Paste API URL and Prompt: "The topic is SageMaker Low-code ML FAQ consisting of 4 questions. Each question should have 4 possible answers."
- Test different FAQs (see the file `bedrock_function-templates.py`)

Concepts:

- Lambda Function review

Inference parameters are values that you can adjust to limit or influence the model response.
Temperature affects the shape of the probability distribution for the predicted output and influences the likelihood of the model selecting lower-probability outputs.
Top P is the percentage of most-likely candidates that the model considers for the next token.

Related assets:

```sh
$ ls
 bedrock_function.py   bedrock_function-templates.py   index.html  'Screenshot from 2024-07-18 15-37-01.png'

```

### Practice: Enhance LLM Capabilities with a Vector Database

Keys:
- Semantic Search can couple with LLM to provide relevant search results that sound like a human


Concepts:
- Semantic search exceeds the limitations of a traditional keyword-based search. unlike lexical search methods that rely solely on word matching, semantic search understands the context and meanings behind words and the complex relationship withing the data, know as syntactic relationships
- LLMs excel at understanding and deriving insights from unstructured data and they have the ability to parse and generalize vast volumes of data. **Combining semantic search with an LLM is known as Retrieval Augmented Generation, or RAG for short.**
- Semantic search capabilities of Amazon OpenSearch to store the embedded vector database
- An embedded vector is a numerical representation of data in our knowledge base. Bringing to the Library example, it is all the information in the library books, convert that information to an embedded vector database, and store it in OpenSearch Service.
- Amazon Sagemaker JumpStart can access a machine learning hub with foundation models, built-in algorithms, and prebuilt machine learning solutions that can be deployed quickly
- Amazon SageMaker Studio also can be used with Jupyter notebook to run all the commands needed to deploy a PoC

Demo steps to build a RAG application by using Amazon OpenSearch Service and Amazon SageMaker:


Practice lab goals:
- deploy embedding LLM by using Amazon SageMaker JumpStart
- Use a Jupyter notebook in SageMaker Studio to prepare raw data
- Create an index and store embedded vector data in Amazno OpenSearch Service
- Explore the data by using OpenSearch Service
- Test a RAG (Retrieval Augmented GEneration) application by requesting a book recommendation

Services used:
- Amazon OpenSearch Service (backed by ElasticSearch)
- CloudFormation to provision resources: cloudformation-template.yaml
- SageMaker Studio
- HuggingFace model `Bloom 7B1 Embeeding FP16`
- SageMaker Classic instance (JupyterLab)

Notes:

- OpenSearch security review: ensure data is encrypted, policy update
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "es:*",
      "Resource": "arn:aws:es:us-east-1:<account_number>:domain/*/*"
    }
  ]
}
```


Steps:

- SageMaker Studio: Choose JumpStart and HuggingFace provider > Search for "Embed" and chose model "Bloom 7B1 Embeeding FP16"
- Deploy the model using instance `ml.g5.2xlarge`
- Check/Copy the SageMaker Endpoint name
- Open SageMaker Studio Classic instance (JupyterLab) and play .*

```sh
$ ls 10-enhance-llm-with-vector-db/
 booksummaries.txt            diy_out1.csv                    'Screenshot from 2024-07-18 16-29-46.png'
 cloudformation-search.yaml   diy_out2.txt                    'Screenshot from 2024-07-18 16-46-03.png'
 cloudformation-user.yaml     llm-with-vector-database.ipynb

```

### Practice: Create Trustworthy LLMs with a Vector Database

Services:
- Bedrock
- Aurora Serverless for Postgress DB
- 


Notes:
- Embeddings models return vectors to be used in a semantic search (RAG)

```sh
$ ls 11-bedrock_kb_postgresql-trustworthy-llm-vectordb/
 bootstrap.sh                               vector_config.sql   winebot.zip   wine-kb.zip
'Screenshot from 2024-07-18 18-19-02.png'   winebot             wine-kb

```

### Practice: Modern data Architectures with LLMs

Goal:
- Query data available in S3 dynamically using natural languages with LLMs
- The LLMs will be tunned using prompt templates to extract relevant information from user's query, producing/transforming prompts with SQL schema to create dynamically SQL queries to retrieve data based in the data schema crawled from S3 using Glue.

Technologies used:
- Jupyter Notebook using Amazon SageMaker
- SQLAlchemy: is a Python SQL toolkit that gives application developers the full power and flexibility of SQL. The toolkit is designed for efficient and high performing database access
- LangChain: used as a helper to create dynamic promps
- Bedrock to serve models and create AI-enabled apps. Transform natural language to SQL queries
- CloudFormation to provision Glue
- S3 to store busines rules crawled by Glue
- Glue to crawler data and create tables on Athena to be able to query by SQL-like
- Amazon SageMaker Studio to explore the data using jupyter notebooks
- Athena to store the structured data (tables) crawled from S3, providing SQL interface to query the data

Assets:

```sh
$ ls ./12-modern-data-architectures-llms/
 cloudformation.yaml                                s3_cars_data.csv
 img-genai-sql-langchain-overall-solution.png       s3_library_data.json
 mda_text_to_sql_langchain_bedrock-EXECUTED.ipynb  'Screenshot from 2024-07-19 10-42-32.png'
 mda_text_to_sql_langchain_bedrock.ipynb

```

### Practice: Serverless Chatbot Using Private Data

Goal:
- Create an app (frontend and chat bot style) to consume private data (PDF files) on S3, indexing it with Kendra, using Mistral7B and Titan models to ask questions for the docs with natural language, fine tunning the prompts with LangChain using RAG. The application frontend is hosted in CloudFront (s3), with API exposed using API Gateway, proxies by Lambda to query the Bedrock.
- The user will compare the results of models Mistral and Titan, fine tuning the RAG
- Create a Chabot application to search private date stored on S3, indexed by Amazon Kendra, served by frontend UI using Amazon Amplify, API Gateway, CloudFront and Lambda.
- Upload data to S3 and Amazon Kendra will index to be readily searchable

Technologies used:
- S3 to store private documents
- Amazon Kendra for intelligent indexing
- Lambda to: 1) integrate intelligent indexing of Amazon Kendra; 2) LangChain for RAG; 3) integrate with Bedrock
- Bedrock
- LangChain
- Bedrock
- FrontEnd UI:
    - Amazon API Gateway->Lambda
    - AWS Amplify to create the App (mobile) and frontend
    - Amazon CloudFront
    - Amazon S3
    - Anazon Cognito for auth the frontend
    - Lambda to query the Kendra index and LangChain libraries for RAG and prompt engineering in Bedrock
- Cloud9 as IDE for development


Templates:

- Tunning prompt to prevent hallucinations:
```sh
You are an intelligent AI advisor, and provide answers to questions by using fact based information. 
Use the following pieces of information to provide a concise answer to the question enclosed in <question> tags. 
Look for the contextual information enclosed in <context> tags.
If you don't know the answer, just say that you don't know, don't try to make up an answer.
<context>{context}</context>
<question>{question}</question>
The response should be specific and use facts only
```

Test1: "Tell me the story about the fox and the tiger"
Response:
I'm sorry, but the context provided does not include a story about a fox and a tiger. The context only discusses Amazon's sustainability efforts and initiatives across its various businesses.

Test2: "What is federal funds rate as of April 2024?"
Response:
The federal funds rate as of May 2, 2024, is in a target range of 5-1/4 to 5-1/2 percent. There is no information provided in the context regarding the federal funds rate as of April 2024.

Test2: "What is federal funds rate as of September 2025?"
Response:
I cannot provide an answer to that question based on the given context. The context only mentions the federal funds rate being left unchanged at a target range of 5¼ to 5½ percent as of September 2023. There is no mention of the federal funds rate in September 2025.

Assets:

```sh
13-serverless-chatbot-private-data]$ ls
 2022-sustainability-report-amazon.pdf   function-load_data_function.py
 cloudformation-LabStack-0.yaml         'Screencast from 2024-07-19 13-57-10.webm'
 cloudformation-LabStack-1.yaml         'Screenshot from 2024-07-19 13-29-02.png'
 function-lab-create-cloud9.py           serverless-chatbot-code.zip

```


### Practice: Improve Code Quality Using Generative AI

Goal:
- Create an AI-code review assistant from a Git repository by reviewing the entire database or an spepcific pull request, review and fix the vulnerabilities based in the report provided by assistant using different FMs.

Technologies:
- Cloud9 as IDE
- CodeCommit as Git repo for streamlit app
- CodeBuild to build app hosted on CodeCommit
- ECR to host container image built by CodeBuild
- ECS Cluster to host Fargate task/container
- EC2 App Load Balancer to expose ECS Fargate service/streamlit app
- Lambda function to be called by app
- Amazon CodeGuru as review assistant running batch reviews
- Bedrock as FM/LLMs interface called by App


Notes:
- Inference refers to the process of generating an output from an input provided to a model. FMs uses probablity to construct the words in a sequence.


commands
```sh
$ aws codecommit create-repository --repository-name code-review-repo
$ git config --global init.defaultBranch main
$ git remote add codecommit "https://git-codecommit.us-east-1.amazonaws.com/v1/repos/code-review-repo"
$ aws codeguru-reviewer associate-repository --repository 'CodeCommit={Name=code-review-repo}'
#... add sources, commit and push to repo
aws codeguru-reviewer create-code-review \
 --name codereview0011 \
 --type '{"RepositoryAnalysis": {"RepositoryHead": {"BranchName": "main"}}}' \
 --repository-association-arn  "arn:aws:codeguru-reviewer:us-east-1:628167599308:association:1175fd0d-9d2a-4c54-b03d-dcac5adaaab1"

```

Sample issue #1 (hashlib):

Enter source code here:
```python
def constructor_noncompliant():
    import hashlib

    text = "ExampleString"

    # Noncompliant: uses the new() constructor instead of the hashlib
    # constructor, which is slower.
    result = hashlib.new("sha256", text.encode())

    print("The hexadecimal equivalent of SHA256 is : ")
    print(result.hexdigest())

```

Enter code analysis finding here:
```text
The constructors for the hashlib module are faster than new(). We recommend using hashlib.sha256() instead.
```

Enter request here:

```text
Refactor the code above to corresponding code analysis finding. Return the fixed code followed by an explanation of how it fixes the issue.
```

Result:

```
Refactored Code:

~~~
import hashlib

text = "ExampleString"

# Compliant: uses the hashlib.sha256() constructor, which is faster.
result = hashlib.sha256(text.encode())

print("The hexadecimal equivalent of SHA256 is : ")
print(result.hexdigest())
~~~

Explanation:

The original code uses the hashlib.new() constructor to create a new hash object for the SHA256 algorithm. However, the hashlib.new() constructor is slower than the specific constructors provided by the hashlib module, such as hashlib.sha256().

In the refactored code, we use the hashlib.sha256() constructor instead of hashlib.new(). This constructor creates a new hash object for the SHA256 algorithm more efficiently, resulting in faster execution.

The rest of the code remains the same, as we still encode the text to bytes before passing it to the constructor and print the hexadecimal equivalent of the SHA256 hash using the hexdigest() method.
```
