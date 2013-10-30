module test1;

class notGood
{
	private:
		int _good;
		int _NotGood;
		
	public:
		int good2;
		int NogGood2;
		int _notGood3;
		
		void BadFunc();
		void GoodFunc();
}

class Good
{
}

struct notGood2
{
}

struct Good2
{
	private:
		int _good;
		int _NotGood;
		
	public:
		int good2;
		int NogGood2;
		int _notGood3;
		
		void BadFunc();
		void GoodFunc();
}