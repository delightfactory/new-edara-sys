class BrowserPrintService {
  private isPrinting = false;

  public async print(): Promise<boolean> {
    if (this.isPrinting) return false;
    this.isPrinting = true;
    
    return new Promise((resolve) => {
      const cleanup = () => {
        window.removeEventListener('afterprint', onAfterPrint);
        window.removeEventListener('beforeprint', onBeforePrint);
        this.isPrinting = false;
        document.body.classList.remove('is-printing');
        resolve(true);
      };

      const onAfterPrint = () => cleanup();
      
      const onBeforePrint = () => {
        document.body.classList.add('is-printing');
      };

      window.addEventListener('afterprint', onAfterPrint);
      window.addEventListener('beforeprint', onBeforePrint);
      
      // Delay to ensure styles and layouts are applied
      setTimeout(() => {
        window.print();
        
        // Safari / iOS fallback if afterprint is unreliable
        setTimeout(() => {
          if (this.isPrinting) {
             cleanup();
          }
        }, 2000); 
      }, 150);
    });
  }
}

export const browserPrintService = new BrowserPrintService();
