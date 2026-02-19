using Documenter
using DescribedTypes

makedocs(
    sitename="DescribedTypes.jl",
    modules=[DescribedTypes],
    checkdocs=:exports,
    format=Documenter.HTML(
        canonical="https://algunion.github.io/DescribedTypes.jl/stable/",
        edit_link="main",
    ),
    pages=[
        "Home" => "index.md",
        "Guide" => "guide.md",
        "API Reference" => "api.md",
        "LLM Reference" => "llm.md",
    ],
)

deploydocs(
    repo="github.com/algunion/DescribedTypes.jl.git",
    devbranch="main",
    push_preview=true,
)
