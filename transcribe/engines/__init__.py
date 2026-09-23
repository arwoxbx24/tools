class _Engine:
    def __init__(self, name, model, key_name, key_file):
        self.name = name
        self.model = model
        self.key_name = key_name
        self.key_file = key_file


groq = _Engine("groq", "whisper-large-v3", "GROQ_API_KEY", "groq.env")
assemblyai = _Engine("assemblyai", "best", "ASSEMBLYAI_API_KEY", "assemblyai.env")

ENGINES = {
    groq.name: groq,
    assemblyai.name: assemblyai,
}
ORDER = [groq.name, assemblyai.name]
BANNED = ("openai", "yandex", "gemini", "openrouter")
