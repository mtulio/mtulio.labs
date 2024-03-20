# Artificial Inteligence | Notes

- [Learning references](#learning)
- [Hands on/DYI](#hands-on--diy)


## Learning

Favorites learning references.

### Video: [You need to learn AI in 2024!][ytb-01]

[ytb-01]: https://www.youtube.com/watch?v=x1TqLcz_ug0

- prompt engineering
- understand the core concepts that dont move quickly
  - Supervisor and non-supervision learning
 
Learn:
- python
- pytorch
- get a supervisor model going
- train a supervised model that solves that problem
- more advanced: move to a classification problem or a segmentation problem

// COURSE //
AI For Everyone by Andrew Ng: https://www.coursera.org/learn/ai-for...

Pytorch Tutorials: https://pytorch.org/tutorials/
Pytorch Github: https://github.com/pytorch/pytorch
Pytorch Tensors: https://pytorch.org/tutorials/beginner/introyt/tensors_deeper_tutorial.html
https://pytorch.org/tutorials/beginner/basics/tensorqs_tutorial.html
https://pytorch.org/tutorials/beginner/basics/autogradqs_tutorial.html

## Hands on/DIY

### privateGPT

- https://github.com/zylon-ai/private-gpt
- https://github.com/zylon-ai/private-gpt?tab=readme-ov-file
- https://docs.privategpt.dev/installation/getting-started/main-concepts
- https://python-poetry.org/docs/#installing-with-the-official-installer
- https://www.trychroma.com/
- https://docs.privategpt.dev/installation/getting-started/installation


Steps in installation page:
```sh
sudo dnf install python3.11 python3.11-devel make
curl -sSL https://install.python-poetry.org | python3 -

# Install ollama https://ollama.com/
curl -fsSL https://ollama.com/install.sh | sh

# Install models to use
ollama pull mistral
ollama pull nomic-embed-text

sudo chown -R mtulio: local_data/
cd private-gpt/
python3.11 -m venv .venv && source .venv/bin/activate
poetry install --extras "ui llms-ollama embeddings-ollama vector-stores-qdrant"
# or
poetry install --extras "ui llms-ollama embeddings-ollama vector-stores-chroma"

# RUn
PGPT_PROFILES=ollama make run

# Use it opening http://localhost:8001
```

## PyTorch

- https://pytorch.org/get-started/locally/

```sh
pip install torch
python3 -m torch torch.cuda.is_available()
```

